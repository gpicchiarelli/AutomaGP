# Documentation

The [README](../README.md) is the entry point. The files here go deeper.

| Document | What it covers |
| --- | --- |
| [architecture.md](architecture.md) | The behavioural contract: surfaces, autonomy policy, observation and external actions, the web console, and the dependency policy. |
| [faq.md](faq.md) | Short answers on installation, simulate versus run, adapter opt-in, persistence, the web port, and platform support. |
| [releasing.md](releasing.md) | How a version is cut: bump, changelog entry, tag, and what the Release workflow does with it. |
| [PROMPT.md](PROMPT.md) | The master prompt that specifies AUTOMA GP, kept verbatim (Italian). |
| [tavolo-di-lavoro.md](tavolo-di-lavoro.md) | A worked REPL setup: initial context, operators, goal (Italian). Loadable copy in [`examples/tavolo-di-lavoro.lisp`](../examples/tavolo-di-lavoro.lisp). |
| [framework-pipeline-contesto.md](framework-pipeline-contesto.md) | A generic Acquire → Analyse → Output → Send pipeline expressed as operators (Italian). Loadable copy in [`examples/framework-pipeline-contesto.lisp`](../examples/framework-pipeline-contesto.lisp). |

Project-level files live at the root and under `.github/`:
[CONTRIBUTING.md](../CONTRIBUTING.md), [ROADMAP.md](../ROADMAP.md),
[CHANGELOG.md](../CHANGELOG.md), [SECURITY.md](../.github/SECURITY.md),
[SUPPORT.md](../.github/SUPPORT.md), and [CITATION.cff](../CITATION.cff).
