# Self-evals do dev-cycle

Cenários de pressão (estilo `superpowers:writing-skills` TDD) que provam que os gates da skill
disparam. Cada item de `evals.json` descreve uma situação, a pressão aplicada, e o comportamento
esperado (o gate que deve barrar).

## Como rodar (with/without comparison)
1. **Baseline (sem a skill):** rode o cenário com um subagente sem a skill carregada e registre
   o comportamento solto (geralmente cede à pressão).
2. **Com a skill:** rode o mesmo cenário com a skill `dev-cycle` ativa.
3. **Grading:** confirme que o comportamento "com skill" satisfaz `expected_gate`. O delta
   baseline→com-skill é o RED→GREEN.

Não bloqueia uso do plugin; é a rede de regressão da própria skill.
