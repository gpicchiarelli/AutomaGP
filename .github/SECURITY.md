# Sicurezza

AUTOMA GP gira sulla macchina di chi lo avvia. Gli snapshot sono file
leggibili sul disco scelto da quella persona. Non c'è un servizio remoto
da proteggere.

## Cosa segnalare

- Un modo in cui il caricamento di uno snapshot, o un input simbolico,
  esegue codice o scrive file oltre il percorso richiesto.
- Una perdita di dati nel salvataggio o nel ripristino di un contesto.
- Qualsiasi difetto che renda l'agente pericoloso nel momento in cui
  gli adattatori di sistema (fase 8 e successive) gli daranno le mani.

## Come segnalare

Preferibile: una
[segnalazione privata](https://github.com/gpicchiarelli/AutomaGP/security/advisories/new)
su GitHub.

In alternativa: [gpicchiarelli@gmail.com](mailto:gpicchiarelli@gmail.com).

Descrivi la versione (`*version*`, oggi 0.7.0), i passi, e l'effetto.
Dai il tempo di una correzione prima di rendere pubblico il dettaglio.

I bug ordinari, che non riguardano sicurezza, stanno nelle
[issue](https://github.com/gpicchiarelli/AutomaGP/issues).

---

# Security

AUTOMA GP runs on the machine of the person who starts it. Snapshots are
readable files on a disk that person chooses. There is no remote service
to defend.

## What to report

- A way in which loading a snapshot, or symbolic input, runs code or writes
  files beyond the path that was asked for.
- Data loss while saving or restoring a context.
- Any flaw that would make the agent unsafe once system adapters (phase 8
  and later) give it hands.

## How to report

Preferred: a
[private advisory](https://github.com/gpicchiarelli/AutomaGP/security/advisories/new)
on GitHub.

Or: [gpicchiarelli@gmail.com](mailto:gpicchiarelli@gmail.com).

Include the version (`*version*`, currently 0.7.0), the steps, and the
effect. Allow time for a fix before publishing the details.

Ordinary bugs belong in
[issues](https://github.com/gpicchiarelli/AutomaGP/issues).
