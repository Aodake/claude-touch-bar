# Claude Touch Bar

Průběh, útrata a ovládání aplikace Claude přímo na Touch Baru MacBooku, s vlastním oknem pro nastavení.

```
✳ 1:34 1/8 │ ▬▬▬░ 3/7 ~4:10 │ ▬▬ 720k │ Sezení 128M $50 │ Dnes 66M $27 │ ↑ Econs portal ●4 │ ⇄ │ ⋯ │ ⤓
```

## Jak se chová

- **V Claudovi** se bar ukáže sám a zabírá celý Touch Bar. **⤓** ho zmenší na normální Touch Bar Macu.
- **Mimo Claude** zůstává v Control Stripu ikona **✳**. Ťuknutím ukážeš Claude bar, v kompaktní velikosti vedle jasu a hlasitosti.
- **⌃⌥C** (Control + Option + C) ukáže nebo schová Claude bar odkudkoliv.
- Schválení a karty s otázkami tě následují i do jiné aplikace, dokud na ně neodpovíš.
- Když Claude dokončí práci a ty jsi jinde, vyskočí `✓ Hotovo: <sezení> │ Otevřít`, zazní zvuk a ✳ bliká.

## Okno aplikace

Otevřeš ho z Launchpadu nebo Spotlightu („Claude Touch Bar“), případně ťuknutím na číslo na Touch Baru. Po zavření aplikace dál běží na pozadí.

- **Přehled:** stav, schválení, kontext, postup plánu, útrata (sezení / 5 h / dnes / týden / měsíc), tempo $/h, aktivní čas, grafy za 24 h a 30 dní, denní rozpočet s odhadem výdrže, změněné soubory.
- **Touch Bar:** editor tří rozložení (Kompaktní, Přehled, Minimal). Položky zapneš, vypneš a přetažením seřadíš. ⇄ mezi rozloženími přepíná na Touch Baru.
- **Napojení na Claude:** hooky, schvalování, karty, zvuky, oprávnění Zpřístupnění.
- **Git a Push:** název a složka repozitáře pro tlačítko ↑.
- **Obecné:** spouštění po přihlášení, ukončení.

## Položky Touch Baru

| Položka | Co ukazuje / dělá |
|---|---|
| Stav a čas | ✳ pracuje, ● čeká, ✓ hotovo; čas tahu; pozice sezení „1/8“. Ťuknutí přenese do Clauda. |
| Postup plánu | `3/7 ~4:10` podle seznamu kroků, který si Claude vede |
| Kontext | zaplnění kontextu, od 70 % oranžové, od 90 % červené |
| Zkomprimovat | nad 80 % kontextu; pošle `/compact` |
| Útrata | sezení, 5 h, dnes, týden, měsíc (tokeny a $) |
| Tempo $/h, Aktivní čas | útrata za poslední hodinu, kolik minut dnes Claude pracoval |
| Graf | útrata po 5 minutách za poslední hodinu |
| Změněné soubory | kolik souborů Claude v sezení upravil (seznam v okně) |
| Čekající sezení | `● 2 čeká`; ťuknutím skočíš na první |
| Commit a push | `↑ Econs portal ●4 ↑1`; pošle do otevřeného chatu „Commitni a pushni změny“ |
| Přepínač modelu | Opus / Fable / Sonnet / Haiku a „Úsilí ▸“ (každý stisk posune úsilí o úroveň) |
| ⋯ | Povolit / Zamítnout, Zastavit, Nové, Push, režim oprávnění, model, sezení, detail |

## Napojení na Claude Code (hooky)

S hooky je stav přesný, ukazuje se aktuální nástroj a plán a jde schvalovat povolení i odpovídat na karty (otázky, box dalšího kroku, nová session) přímo z Touch Baru. Zapnou se v okně (Napojení na Claude → Zapnout) nebo příkazem:

```bash
"$HOME/Applications/Claude Touch Bar.app/Contents/MacOS/ClaudeTouchBar" --install-hooks
```

Hooky se přidají do `~/.claude/settings.json` (ostatní zůstanou, záloha v `settings.json.bak-claudetouchbar`). V režimu *Auto* se Claude na povolení neptá, takže tam schvalovací bar nevyskočí. Události se zapisují do `~/Library/Application Support/ClaudeTouchBar/hooks.log`.

## Odkud jsou data

Code tab zapisuje přepisy sezení do `~/.claude/projects/**.jsonl`. Aplikace je jen čte, nic neposílá po síti a nesahá na přihlašovací údaje. Chat tab tokeny lokálně neukládá. Cena je orientační přepočet podle API ceníku, předplatné se po tokenech neplatí.

## Instalace

```bash
./install.sh
```

Sestaví aplikaci, zkopíruje ji do `~/Applications`, zapne spouštění po přihlášení a otevře okno. Ovládání okna Clauda (Zastavit, Nové, Push, režim, model, karty) potřebuje oprávnění **Zpřístupnění**. Aby vydrželo i po nových verzích, `build.sh` podepisuje certifikátem **ClaudeTouchBar Local** (Přístup ke klíčence → Asistent pro certifikáty → Vytvořit certifikát, typ *Podepisování kódu*).

## Odinstalace

```bash
"$HOME/Applications/Claude Touch Bar.app/Contents/MacOS/ClaudeTouchBar" --uninstall-hooks; pkill -x ClaudeTouchBar; rm -f ~/Library/LaunchAgents/local.ClaudeTouchBar.plist; rm -rf "$HOME/Applications/Claude Touch Bar.app"
```

## Technická poznámka

Zobrazení nad jinými aplikacemi a ikona v Control Stripu používají neveřejné API Touch Baru (stejně jako MTMR nebo Pock), ovládání okna Clauda jde přes rozhraní Zpřístupnění. Kdyby budoucí macOS nebo nová verze Clauda něco z toho změnila, aplikace nespadne, jen daná funkce přestane fungovat.
