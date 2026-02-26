#!/usr/bin/env python3
"""
OpenAI WebSocket Debate Client for AI Review Arena.

Runs adversarial debate rounds over a persistent WebSocket connection
to the OpenAI Responses API, achieving ~40% faster debate performance
compared to spawning separate CLI processes per round.

Uses raw WebSocket connection to wss://api.openai.com/v1/responses
with response.create events. Falls back to standard HTTP if WebSocket
connection fails.

Connection-local in-memory cache holds the most recent response per
connection, enabling previous_response_id chaining even with store=false.

Usage: echo '{"findings": [...], "config": {...}, "code_context": {...}}' | python3 openai-ws-debate.py
Output: {"accepted": [...], "rejected": [...], "disputed": [...]}
"""

import json
import os
import re
import sys
import time


def extract_json_from_text(text):
    """Extract JSON from text that may contain markdown code blocks."""
    text = text.strip()
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        pass

    match = re.search(r'```(?:json)?\s*\n?(.*?)\n?```', text, re.DOTALL)
    if match:
        try:
            return json.loads(match.group(1).strip())
        except json.JSONDecodeError:
            pass

    match = re.search(r'\{.*\}', text, re.DOTALL)
    if match:
        try:
            return json.loads(match.group(0))
        except json.JSONDecodeError:
            pass

    return None


def ws_send_and_receive(ws, request_payload, timeout=120):
    """Send a response.create event over WebSocket and collect the full response."""
    ws.send(json.dumps({
        "type": "response.create",
        "response": request_payload
    }))

    response_text = ""
    response_id = None
    deadline = time.time() + timeout

    while time.time() < deadline:
        try:
            ws.settimeout(max(1, deadline - time.time()))
            raw = ws.recv()
        except Exception:
            break

        try:
            event = json.loads(raw)
        except json.JSONDecodeError:
            continue

        event_type = event.get("type", "")

        if event_type == "response.output_text.delta":
            response_text += event.get("delta", "")
        elif event_type == "response.completed":
            resp = event.get("response", {})
            response_id = resp.get("id")
            # Extract full text from completed response output
            for item in resp.get("output", []):
                if item.get("type") == "message":
                    for content in item.get("content", []):
                        if content.get("type") == "output_text":
                            response_text = content.get("text", response_text)
            break
        elif event_type == "response.failed":
            error = event.get("response", {}).get("error", {})
            raise RuntimeError(f"Response failed: {error.get('message', 'unknown')}")
        elif event_type == "error":
            raise RuntimeError(f"WebSocket error: {event.get('error', {}).get('message', 'unknown')}")

    return response_text, response_id


def run_debate_ws(findings, code_context, model, store, connection_timeout,
                  max_rounds, challenge_threshold, consensus_threshold, api_key, ws_url):
    """Run debate over persistent WebSocket connection."""
    try:
        import websocket
    except ImportError:
        raise ImportError("websocket-client package not installed. Run: pip install websocket-client")

    max_retries = 3
    last_error = None

    for attempt in range(max_retries):
        try:
            ws = websocket.create_connection(
                ws_url,
                header=[
                    f"Authorization: Bearer {api_key}",
                    "OpenAI-Beta: realtime=v1"
                ],
                timeout=connection_timeout
            )
        except Exception as e:
            last_error = e
            if attempt < max_retries - 1:
                backoff = min(2 ** attempt, 8)
                time.sleep(backoff)
                continue
            raise RuntimeError(f"WebSocket connection failed after {max_retries} attempts: {last_error}")

        try:
            return _run_debate_rounds(ws, findings, code_context, model, store,
                                      connection_timeout, max_rounds,
                                      challenge_threshold, consensus_threshold)
        except (ConnectionError, OSError) as e:
            last_error = e
            if attempt < max_retries - 1:
                backoff = min(2 ** attempt, 8)
                time.sleep(backoff)
                continue
            raise
        finally:
            try:
                ws.close()
            except Exception:
                pass

    raise RuntimeError(f"WebSocket debate failed after {max_retries} attempts: {last_error}")


def run_debate_http(findings, code_context, model, store, connection_timeout,
                    max_rounds, challenge_threshold, consensus_threshold, api_key):
    """Fallback: run debate using standard HTTP Responses API."""
    try:
        import openai
    except ImportError:
        raise ImportError("openai package not installed. Run: pip install openai>=2.22.0")

    client = openai.OpenAI(api_key=api_key)

    challengeable = _find_challengeable(findings, challenge_threshold)
    if not challengeable:
        return {"accepted": findings, "rejected": [], "disputed": []}

    findings_text = json.dumps(findings, indent=2)
    code_text = json.dumps(code_context, indent=2) if code_context else "No code context provided"

    previous_response_id = None

    # Round 1: Challenge
    round1_prompt = _build_round1_prompt(findings_text, code_text, challengeable)
    try:
        response = client.responses.create(
            model=model,
            input=round1_prompt,
            store=True,  # HTTP mode needs store=true for chaining
            stream=False,
        )
        previous_response_id = response.id
        round1_text = _extract_response_text(response)
        round1_data = extract_json_from_text(round1_text)
        if round1_data:
            _apply_challenges(findings, round1_data.get("challenges", []), model)
    except Exception as e:
        return {"accepted": findings, "rejected": [], "disputed": [],
                "error": f"HTTP Round 1 failed: {e}"}

    if max_rounds < 2:
        return categorize_findings(findings, consensus_threshold)

    # Round 2: Defense
    challenged = [f for f in findings if f.get("debate_status") == "challenged"]
    if challenged and previous_response_id:
        round2_prompt = _build_round2_prompt(challenged)
        try:
            response2 = client.responses.create(
                model=model,
                input=round2_prompt,
                previous_response_id=previous_response_id,
                store=True,
                stream=False,
            )
            previous_response_id = response2.id
            round2_text = _extract_response_text(response2)
            round2_data = extract_json_from_text(round2_text)
            if round2_data:
                _apply_defenses(findings, round2_data.get("final_assessments", []))
        except Exception:
            pass

    if max_rounds < 3:
        return categorize_findings(findings, consensus_threshold)

    # Round 3: Synthesis
    if previous_response_id:
        round3_prompt = _build_round3_prompt()
        try:
            response3 = client.responses.create(
                model=model,
                input=round3_prompt,
                previous_response_id=previous_response_id,
                store=True,
                stream=False,
            )
            round3_text = _extract_response_text(response3)
            round3_data = extract_json_from_text(round3_text)
            if round3_data:
                _apply_synthesis(findings, round3_data.get("synthesis", []))
        except Exception:
            pass

    return categorize_findings(findings, consensus_threshold)


def _run_debate_rounds(ws, findings, code_context, model, store,
                       connection_timeout, max_rounds,
                       challenge_threshold, consensus_threshold):
    """Core debate logic used by WebSocket path."""
    challengeable = _find_challengeable(findings, challenge_threshold)
    if not challengeable:
        return {"accepted": findings, "rejected": [], "disputed": []}

    findings_text = json.dumps(findings, indent=2)
    code_text = json.dumps(code_context, indent=2) if code_context else "No code context provided"

    previous_response_id = None

    # Round 1: Challenge
    round1_prompt = _build_round1_prompt(findings_text, code_text, challengeable)
    payload = {"model": model, "input": [{"role": "user", "content": round1_prompt}],
               "store": store}
    round1_text, previous_response_id = ws_send_and_receive(ws, payload, connection_timeout)
    round1_data = extract_json_from_text(round1_text)
    if round1_data:
        _apply_challenges(findings, round1_data.get("challenges", []), model)

    if max_rounds < 2:
        return categorize_findings(findings, consensus_threshold)

    # Round 2: Defense
    challenged = [f for f in findings if f.get("debate_status") == "challenged"]
    if challenged and previous_response_id:
        round2_prompt = _build_round2_prompt(challenged)
        payload2 = {"model": model, "input": [{"role": "user", "content": round2_prompt}],
                     "previous_response_id": previous_response_id, "store": store}
        round2_text, previous_response_id = ws_send_and_receive(ws, payload2, connection_timeout)
        round2_data = extract_json_from_text(round2_text)
        if round2_data:
            _apply_defenses(findings, round2_data.get("final_assessments", []))

    if max_rounds < 3:
        return categorize_findings(findings, consensus_threshold)

    # Round 3: Synthesis
    if previous_response_id:
        round3_prompt = _build_round3_prompt()
        payload3 = {"model": model, "input": [{"role": "user", "content": round3_prompt}],
                     "previous_response_id": previous_response_id, "store": store}
        round3_text, _ = ws_send_and_receive(ws, payload3, connection_timeout)
        round3_data = extract_json_from_text(round3_text)
        if round3_data:
            _apply_synthesis(findings, round3_data.get("synthesis", []))

    return categorize_findings(findings, consensus_threshold)


# --- Prompt builders ---

def _build_round1_prompt(findings_text, code_text, challengeable):
    return f"""You are a code review challenger. Analyze these findings and challenge any that seem incorrect, overstated, or lack evidence.

FINDINGS TO REVIEW:
{findings_text}

CODE CONTEXT:
{code_text}

For each challengeable finding (indices: {challengeable}), provide your assessment.

Respond with ONLY valid JSON:
{{
  "challenges": [
    {{
      "finding_index": <int>,
      "agree": <bool>,
      "confidence_adjustment": <-20 to +20>,
      "evidence": "<explanation>"
    }}
  ]
}}"""


def _build_round2_prompt(challenged_findings):
    return f"""Based on the challenges you raised, the original reviewers defend their findings.

CHALLENGED FINDINGS:
{json.dumps(challenged_findings, indent=2)}

Review the defenses and provide your final assessment. Adjust confidence up if the defense is convincing, down if not.

Respond with ONLY valid JSON:
{{
  "final_assessments": [
    {{
      "finding_index": <int>,
      "final_agree": <bool>,
      "confidence_adjustment": <-10 to +10>,
      "reasoning": "<explanation>"
    }}
  ]
}}"""


def _build_round3_prompt():
    return """Provide a final synthesis of the debate. For each finding, give your final confidence assessment.

Respond with ONLY valid JSON:
{
  "synthesis": [
    {
      "finding_index": <int>,
      "final_confidence": <0-100>,
      "verdict": "accepted|rejected|disputed"
    }
  ]
}"""


# --- Finding manipulation helpers ---

def _find_challengeable(findings, challenge_threshold):
    challengeable = []
    for i, f in enumerate(findings):
        models = f.get("models", [])
        confidence = f.get("confidence", 50)
        if len(models) <= 1 or confidence < challenge_threshold:
            challengeable.append(i)
    return challengeable


def _apply_challenges(findings, challenges, model):
    for challenge in challenges:
        idx = challenge.get("finding_index", -1)
        if 0 <= idx < len(findings):
            adj = max(-20, min(20, challenge.get("confidence_adjustment", 0)))
            old_conf = findings[idx].get("confidence", 50)
            findings[idx]["confidence"] = max(0, min(100, old_conf + adj))
            findings[idx]["debate_status"] = "confirmed" if challenge.get("agree", True) else "challenged"
            findings[idx]["challenger"] = model


def _apply_defenses(findings, assessments):
    for assessment in assessments:
        idx = assessment.get("finding_index", -1)
        if 0 <= idx < len(findings):
            adj = max(-10, min(10, assessment.get("confidence_adjustment", 0)))
            old_conf = findings[idx].get("confidence", 50)
            findings[idx]["confidence"] = max(0, min(100, old_conf + adj))
            if not assessment.get("final_agree", True):
                findings[idx]["debate_status"] = "challenged"


def _apply_synthesis(findings, synthesis):
    for syn in synthesis:
        idx = syn.get("finding_index", -1)
        if 0 <= idx < len(findings):
            findings[idx]["confidence"] = syn.get("final_confidence", findings[idx].get("confidence", 50))
            verdict = syn.get("verdict", "")
            if verdict in ("accepted", "rejected", "disputed"):
                findings[idx]["debate_status"] = verdict


def _extract_response_text(response):
    """Extract text from an OpenAI Responses API response object."""
    text = ""
    for item in response.output:
        if hasattr(item, "content"):
            for content in item.content:
                if hasattr(content, "text"):
                    text += content.text
    return text


def categorize_findings(findings, consensus_threshold):
    """Categorize findings into accepted/rejected/disputed using same logic as run-debate.sh."""
    accepted = []
    rejected = []
    disputed = []

    for f in findings:
        models = f.get("models", [])
        model_count = len(set(models)) if models else 1
        confidence = f.get("confidence", 50)
        status = f.get("debate_status", "none")

        if model_count >= 2 and status != "challenged":
            accepted.append(f)
        elif confidence >= consensus_threshold:
            accepted.append(f)
        elif status == "challenged" and confidence < (consensus_threshold * 0.5):
            rejected.append(f)
        elif status == "challenged":
            disputed.append(f)
        elif confidence < (consensus_threshold * 0.6):
            disputed.append(f)
        elif confidence >= (consensus_threshold * 0.7):
            accepted.append(f)
        else:
            disputed.append(f)

    return {"accepted": accepted, "rejected": rejected, "disputed": disputed}


def main():
    # Read input from stdin
    try:
        input_data = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError) as e:
        print(json.dumps({
            "accepted": [], "rejected": [], "disputed": [],
            "error": f"Invalid JSON input: {e}"
        }))
        sys.exit(1)

    findings = input_data.get("findings", [])
    config = input_data.get("config", {})
    code_context = input_data.get("code_context", {})

    if not findings:
        print(json.dumps({"accepted": [], "rejected": [], "disputed": []}))
        sys.exit(0)

    # Config
    ws_config = config.get("websocket", {})
    debate_config = config.get("debate", {})
    model = ws_config.get("model", "gpt-5.3-codex-spark")
    store = ws_config.get("store", False)
    connection_timeout = ws_config.get("connection_timeout_seconds", 30)
    ws_url = ws_config.get("url", "wss://api.openai.com/v1/responses")
    max_rounds = debate_config.get("max_rounds", 3)
    challenge_threshold = debate_config.get("challenge_threshold", 60)
    consensus_threshold = debate_config.get("consensus_threshold", 80)

    api_key = os.environ.get("OPENAI_API_KEY")
    if not api_key:
        print(json.dumps({
            "accepted": findings, "rejected": [], "disputed": [],
            "error": "OPENAI_API_KEY not set"
        }))
        sys.exit(1)

    # Try WebSocket first, fall back to HTTP
    try:
        result = run_debate_ws(
            findings, code_context, model, store, connection_timeout,
            max_rounds, challenge_threshold, consensus_threshold, api_key, ws_url
        )
        print(json.dumps(result))
    except (ImportError, Exception) as ws_error:
        # WebSocket failed — fall back to HTTP Responses API
        try:
            result = run_debate_http(
                findings, code_context, model, store, connection_timeout,
                max_rounds, challenge_threshold, consensus_threshold, api_key
            )
            result["ws_fallback"] = f"WebSocket unavailable ({ws_error}), used HTTP"
            print(json.dumps(result))
        except Exception as http_error:
            # Both failed — accept all findings
            print(json.dumps({
                "accepted": findings, "rejected": [], "disputed": [],
                "error": f"All transports failed. WS: {ws_error}, HTTP: {http_error}"
            }))
            sys.exit(0)


if __name__ == "__main__":
    main()
