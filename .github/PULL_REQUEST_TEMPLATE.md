## Perché · Why

<!-- Quale parte del senso del progetto migliora questa modifica?
     Which part of the project's purpose does this change serve? -->

## Cosa cambia · What changes

<!-- Una modifica per pull request. Se ne servono due, servono due PR.
     One change per pull request. If it takes two, it takes two PRs. -->

## Verifica · Checks

- [ ] `./scripts/run-tests.sh` passa in locale · passes locally
- [ ] Test FiveAM aggiunti o estesi per il comportamento nuovo · tests added or extended
- [ ] `version.lisp` e `version.lisp-expr` aggiornati insieme, con la voce in `CHANGELOG.md`
- [ ] README, roadmap e changelog restano fedeli a ciò che il codice sa fare · docs stay faithful
- [ ] Nessuna capacità di una fase successiva viene presentata come già pronta · nothing is announced early
- [ ] Se tocca `macos/`: `swift build` passa · if `macos/` changed, `swift build` passes
