---
name: question
description: >-
  Use only when $question is explicitly invoked: read-only discussion in the user's language with precise technical terms and ASCII
  diagrams.
---

# Question

## Preserve the read-only boundary

- Treat the current request as discussion only.
- Do not create, modify, move, or delete files.
- Do not update plans, logs, checkpoints, or project status.
- Do not perform operations that change the state of Git, dependencies, configuration, external systems, or remote
  services.
- Perform read-only inspection or research only when it is genuinely necessary to answer the question.
- If the user requests both discussion and modifications in the same request, remain read-only and explain that the
  modifications require a new request that does not invoke `$question`.
- Do not automatically turn the user's ideas into formal tasks or persistent records.

## Handle voice input

- Assume the user's message may have been transcribed from speech.
- Correct obvious transcription errors directly when the intended meaning is clear.
- State the current interpretation first when an ambiguity would materially affect the answer.
- Do not interrupt a normal discussion over minor transcription errors.

## Language

- Respond in the user's language unless they request another language.
- Preserve English technical terms when they help understanding or searching; explain them in the conversation's
  language when useful. Preserve code identifiers, commands, filenames, and product names as written.
- Repository content must follow the English policy in `AGENTS.md`. This discussion skill does not authorize saving
  files in any language.

## Format diagrams

- Do not use Mermaid.
- Do not generate images unless the user explicitly requests them.
- When a process, hierarchy, or relationship needs a diagram, use an ASCII code block labeled `text`.
- Use only plain characters in ASCII diagrams, such as `+`, `-`, `|`, `>`, `<`, `[`, and `]`.
- Keep diagrams concise and ensure they remain readable when copied into Markdown.

Example:

```text
[User Input]
     |
     v
[Discussion]
     |
     v
[Answer Only]
```

## Answer effectively

- Answer the core question directly before adding detail.
- Use headings or lists only when the question's complexity warrants them.
- Distinguish known facts, reasonable inferences, and personal recommendations.
- State uncertainty explicitly.
- Do not over-format simple answers.
- Do not claim in the final response that any files were modified.

## Exit read-only mode

Apply this skill only to the request in which it is invoked.

When the user needs something recorded or modified, ask them to request the modification explicitly without invoking `$question`.
