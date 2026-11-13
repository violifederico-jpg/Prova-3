# Git Flow – laboratorio finale

Laboratorio per esercitare **Git Flow** con due branch permanenti e tre famiglie di branch temporanei.

## Branch permanenti
- **main**: contiene le versioni stabili rilasciate; riceve release e hotfix.
- **develop**: integra lo sviluppo destinato alla prossima release.

## Branch temporanei
| Branch | Origine | Destinazione |
| --- | --- | --- |
| `feature/<nome>` | develop | develop |
| `release/<versione>` | develop | main e develop |
| `hotfix/<versione>` | main | main e develop (e release aperta, se serve) |

Le famiglie feature, release e hotfix sono *convenzioni di naming*: i branch non vanno creati in anticipo. In questo setup è creato soltanto il branch permanente `develop`.

## Esercizio finale
1. Creare `feature/login` da develop; eseguire commit e aprire PR verso develop.
2. Creare `release/1.0.0` da develop; correggere un difetto di stabilizzazione; aprire PR verso main e develop.
3. Dopo l'integrazione su main, creare il tag annotato `v1.0.0`.
4. Creare `hotfix/1.0.1` da main; correggere un difetto urgente; integrare su main e develop; creare tag `v1.0.1`.
5. Usare Git Graph o `git log --graph --oneline --decorate --all` per interpretare la storia.

## Protezioni consigliate
Su GitHub configurare ruleset o branch protection **sia per main sia per develop**:
- Pull Request obbligatoria, con una review approvata quando ci sono revisori disponibili;
- vietare force push e cancellazione;
- non consentire bypass agli sviluppatori, nei limiti del piano GitHub;
- richiedere i check CI solo dopo aver creato una pipeline funzionante.

Per esercitare la topologia classica Git Flow, sulle PR di release e hotfix scegliere **Create a merge commit** invece di squash o rebase. Verificare i permessi e la disponibilità effettiva delle regole: sui repository pubblici personali l'applicazione dei ruleset dipende dal piano.

## Comandi di ispezione
```bash
git fetch origin
git branch -a
git log --graph --oneline --decorate --all
```
