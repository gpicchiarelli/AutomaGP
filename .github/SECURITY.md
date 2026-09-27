# Sicurezza

AUTOMA GP gira sulla macchina di chi lo avvia. Gli snapshot sono file
leggibili sul disco scelto da quella persona. Non c'è un servizio remoto
da proteggere.

## Versioni seguite

Solo l'ultima versione su `main` (il valore in `version.lisp-expr`) riceve
correzioni. Le versioni precedenti non vengono mantenute.

## Cosa segnalare

- Un modo in cui il caricamento di uno snapshot, o un input simbolico,
  esegue codice o scrive file oltre il percorso richiesto.
- Una perdita di dati nel salvataggio o nel ripristino di un contesto.
- Un modo in cui un'esecuzione con adattatori tocca il computer oltre
  l'azione esterna che il piano ha dichiarato, o senza la conferma
  richiesta dalla policy.

## Come segnalare

Preferibile: una
[segnalazione privata](https://github.com/gpicchiarelli/AutomaGP/security/advisories/new)
su GitHub.

In alternativa: [gpicchiarelli@gmail.com](mailto:gpicchiarelli@gmail.com).

Descrivi la versione (`*version*` in `version.lisp`), i passi, e l'effetto.
Dai il tempo di una correzione prima di rendere pubblico il dettaglio:
una prima risposta entro sette giorni, una correzione o una spiegazione
entro novanta. Chi segnala viene nominato nel changelog, se lo desidera.

I bug ordinari, che non riguardano sicurezza, stanno nelle
[issue](https://github.com/gpicchiarelli/AutomaGP/issues).

---

# Security

AUTOMA GP runs on the machine of the person who starts it. Snapshots are
readable files on a disk that person chooses. There is no remote service
to defend.

## Supported versions

Only the latest version on `main` (the value in `version.lisp-expr`)
receives fixes. Earlier versions are not maintained.

## What to report

- A way in which loading a snapshot, or symbolic input, runs code or writes
  files beyond the path that was asked for.
- Data loss while saving or restoring a context.
- A way in which an execute with adapters touches the computer beyond the
  external action the plan declared, or without the confirmation the
  policy requires.

## How to report

Preferred: a
[private advisory](https://github.com/gpicchiarelli/AutomaGP/security/advisories/new)
on GitHub.

Or: [gpicchiarelli@gmail.com](mailto:gpicchiarelli@gmail.com).

Include the version (`*version*` in `version.lisp`), the steps, and the
effect. Allow time for a fix before publishing the details: a first reply
within seven days, a fix or an explanation within ninety. Reporters are
credited in the changelog if they wish.

Ordinary bugs belong in
[issues](https://github.com/gpicchiarelli/AutomaGP/issues).
