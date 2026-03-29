#!/usr/bin/env python3
"""
ai-review-arena: Streaming Review Engine

Uses OpenAI and Google GenAI Python SDKs for true streaming reviews.
Writes findings in real-time to signal log as JSONL.

Usage:
  stream-review.py codex <file-path> <role> [--config <config-file>]
  stream-review.py gemini <file-path> <role> [--config <config-file>]

Environment:
  SESSION_DIR          - Session directory for signal log and findings
  OPENAI_API_KEY       - Required for Codex streaming
  GOOGLE_API_KEY       - Required for Gemini streaming
  STREAM_PROMPT_FILE   - Path to role-specific prompt template
  STREAM_TIMEOUT       - Timeout in seconds (default: 120)
"""

import argparse
import fcntl
import json
import os
import re
import sys
import time
from datetime import datetime, timezone
from pathlib import Path


def atomic_append(filepath: str, line: str):
    """Append a line to a file with flock-based locking."""
    with open(filepath, 'a') as f:
        fcntl.flock(f.fileno(), fcntl.LOCK_EX)
        try:
            f.write(line + '\n')
            f.flush()
        finally:
            fcntl.flock(f.fileno(), fcntl.LOCK_UN)


def write_signal(signal_log: str, source: str, signal_type: str, data: dict):
    """Write a signal entry to the JSONL signal log."""
    entry = {
        'ts': datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%S.%f')[:-3] + 'Z',
        'source': source,
        'type': signal_type,
        'data': data,
    }
    atomic_append(signal_log, json.dumps(entry, ensure_ascii=False))


def extract_findings_from_text(text: str) -> list:
    """Try to extract JSON finding objects from accumulated text."""
    findings = []

    # Try to parse as complete JSON first
    try:
        parsed = json.loads(text)
        if isinstance(parsed, dict) and 'findings' in parsed:
            return parsed['findings']
        if isinstance(parsed, list):
            return parsed
        if isinstance(parsed, dict) and 'title' in parsed:
            return [parsed]
    except json.JSONDecodeError:
        pass

    # Try to find JSON objects in the text
    # Match individual JSON objects (greedy between { and })
    for match in re.finditer(r'\{[^{}]*"title"[^{}]*\}', text):
        try:
            obj = json.loads(match.group())
            if 'title' in obj:
                findings.append(obj)
        except json.JSONDecodeError:
            continue

    # Try markdown code blocks
    for block_match in re.finditer(r'```(?:json)?\s*\n(.*?)\n```', text, re.DOTALL):
        block = block_match.group(1).strip()
        try:
            parsed = json.loads(block)
            if isinstance(parsed, list):
                findings.extend(parsed)
            elif isinstance(parsed, dict) and 'findings' in parsed:
                findings.extend(parsed['findings'])
            elif isinstance(parsed, dict) and 'title' in parsed:
                findings.append(parsed)
        except json.JSONDecodeError:
            pass

    return findings


def build_prompt(file_path: str, file_content: str, role: str, prompt_file: str) -> str:
    """Build the review prompt from template and file content."""
    template = ""
    if os.path.exists(prompt_file):
        with open(prompt_file, 'r') as f:
            template = f.read()

    return f"""{template}

--- FILE: {file_path} ---
{file_content}
--- END FILE ---

---
[CORE INSTRUCTION REPEAT]
Review the code above for {role} issues in file {file_path}. Return findings as structured JSON with fields: severity (critical|high|medium|low), title, description, file, line, and suggestion. Output must be valid JSON only.
"""


def stream_codex(file_path: str, role: str, prompt: str, session_dir: str,
                 model: str = "gpt-5.4", timeout: int = 120) -> list:
    """Stream review using OpenAI API (Responses API or Chat Completions)."""
    from openai import OpenAI

    client = OpenAI()
    signal_log = os.path.join(session_dir, 'signals.jsonl')
    all_findings = []
    accumulated_text = ""
    seen_findings = set()

    try:
        # Use streaming chat completion
        stream = client.chat.completions.create(
            model=model,
            messages=[
                {"role": "system", "content": "You are a code reviewer. Output findings as JSON."},
                {"role": "user", "content": prompt}
            ],
            stream=True,
            timeout=timeout,
        )

        for chunk in stream:
            if chunk.choices and chunk.choices[0].delta.content:
                delta = chunk.choices[0].delta.content
                accumulated_text += delta

                # Try to extract findings from accumulated text periodically
                new_findings = extract_findings_from_text(accumulated_text)
                for finding in new_findings:
                    # Deduplicate by title+file+line
                    key = f"{finding.get('title', '')}:{finding.get('file', '')}:{finding.get('line', 0)}"
                    if key not in seen_findings:
                        seen_findings.add(key)
                        finding.setdefault('file', file_path)
                        all_findings.append(finding)

                        # Write real-time signal
                        write_signal(signal_log, 'codex', 'finding_stream', finding)

                        # Alert on critical findings immediately
                        if finding.get('severity') == 'critical':
                            write_signal(signal_log, 'codex', 'critical_alert', {
                                'title': finding.get('title', ''),
                                'file': finding.get('file', file_path),
                                'line': finding.get('line', 0),
                            })

    except Exception as e:
        write_signal(signal_log, 'codex', 'error', {
            'message': str(e)[:500],
            'role': role,
        })

    # Final parse attempt on complete text
    if not all_findings:
        all_findings = extract_findings_from_text(accumulated_text)
        for f in all_findings:
            f.setdefault('file', file_path)
            write_signal(signal_log, 'codex', 'finding_stream', f)

    return all_findings


def stream_gemini(file_path: str, role: str, prompt: str, session_dir: str,
                  model: str = "gemini-3-pro-preview", timeout: int = 120) -> list:
    """Stream review using Google GenAI API."""
    signal_log = os.path.join(session_dir, 'signals.jsonl')
    all_findings = []
    accumulated_text = ""
    seen_findings = set()

    try:
        import google.genai as genai

        client = genai.Client()

        stream = client.models.generate_content_stream(
            model=model,
            contents=prompt,
        )

        for chunk in stream:
            if chunk.text:
                accumulated_text += chunk.text

                new_findings = extract_findings_from_text(accumulated_text)
                for finding in new_findings:
                    key = f"{finding.get('title', '')}:{finding.get('file', '')}:{finding.get('line', 0)}"
                    if key not in seen_findings:
                        seen_findings.add(key)
                        finding.setdefault('file', file_path)
                        all_findings.append(finding)

                        write_signal(signal_log, 'gemini', 'finding_stream', finding)

                        if finding.get('severity') == 'critical':
                            write_signal(signal_log, 'gemini', 'critical_alert', {
                                'title': finding.get('title', ''),
                                'file': finding.get('file', file_path),
                                'line': finding.get('line', 0),
                            })

    except ImportError:
        # Fallback: try google.generativeai (older SDK)
        try:
            import google.generativeai as genai_old

            genai_old.configure()
            gen_model = genai_old.GenerativeModel(model)

            response = gen_model.generate_content(prompt, stream=True)
            for chunk in response:
                if chunk.text:
                    accumulated_text += chunk.text
                    new_findings = extract_findings_from_text(accumulated_text)
                    for finding in new_findings:
                        key = f"{finding.get('title', '')}:{finding.get('file', '')}:{finding.get('line', 0)}"
                        if key not in seen_findings:
                            seen_findings.add(key)
                            finding.setdefault('file', file_path)
                            all_findings.append(finding)
                            write_signal(signal_log, 'gemini', 'finding_stream', finding)

        except Exception as e:
            write_signal(signal_log, 'gemini', 'error', {
                'message': str(e)[:500],
                'role': role,
            })

    except Exception as e:
        write_signal(signal_log, 'gemini', 'error', {
            'message': str(e)[:500],
            'role': role,
        })

    if not all_findings:
        all_findings = extract_findings_from_text(accumulated_text)
        for f in all_findings:
            f.setdefault('file', file_path)
            write_signal(signal_log, 'gemini', 'finding_stream', f)

    return all_findings


def main():
    parser = argparse.ArgumentParser(description='Streaming Review Engine')
    parser.add_argument('model', choices=['codex', 'gemini'], help='Model to use')
    parser.add_argument('file_path', help='Path to file being reviewed')
    parser.add_argument('role', help='Review role')
    parser.add_argument('--config', default='', help='Config file path')
    parser.add_argument('--session-dir', default=os.environ.get('SESSION_DIR', '/tmp/ai-review-arena'),
                        help='Session directory')
    args = parser.parse_args()

    # Read file content
    try:
        with open(args.file_path, 'r', encoding='utf-8', errors='ignore') as f:
            file_content = f.read()
    except Exception as e:
        print(json.dumps({
            'model': args.model, 'role': args.role, 'file': args.file_path,
            'error': str(e), 'findings': []
        }))
        sys.exit(0)

    # Resolve prompt file
    script_dir = Path(__file__).parent
    plugin_dir = script_dir.parent
    prompt_file = str(plugin_dir / 'config' / 'review-prompts' / f'{args.role}.txt')

    # Load config
    model_variant = ""
    timeout = 120
    if args.config and os.path.exists(args.config):
        try:
            with open(args.config) as f:
                config = json.load(f)
            timeout = config.get('timeout', config.get('fallback', {}).get('external_cli_timeout_seconds', 120))
            if args.model == 'codex':
                model_variant = config.get('models', {}).get('codex', {}).get('model_variant', 'gpt-5.4')
            else:
                model_variant = config.get('models', {}).get('gemini', {}).get('model_variant', 'gemini-3-pro-preview')
        except Exception:
            pass

    if not model_variant:
        model_variant = 'gpt-5.4' if args.model == 'codex' else 'gemini-3-pro-preview'

    # Build prompt
    prompt = build_prompt(args.file_path, file_content, args.role, prompt_file)

    # Ensure session dir exists
    os.makedirs(args.session_dir, exist_ok=True)

    # Stream review
    if args.model == 'codex':
        findings = stream_codex(args.file_path, args.role, prompt, args.session_dir,
                                model=model_variant, timeout=timeout)
    else:
        findings = stream_gemini(args.file_path, args.role, prompt, args.session_dir,
                                 model=model_variant, timeout=timeout)

    # Output normalized JSON
    output = {
        'model': args.model,
        'role': args.role,
        'file': args.file_path,
        'findings': findings,
        'summary': f"Streaming review completed. Found {len(findings)} issues.",
        'streaming': True,
    }
    print(json.dumps(output, ensure_ascii=False))


if __name__ == '__main__':
    main()
