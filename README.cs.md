# Claude Touch Bar

[English](README.md) · **Česky**

Průběh, útrata a ovládání desktopové aplikace Claude přímo na Touch Baru MacBooku, s vlastním oknem pro nastavení.

```
✳ 1:34 1/8 │ ▬▬▬░ 3/7 ~4:10 │ ▬▬ 720k │ Sezení 128M $50 │ Dnes 66M $27 │ ↑ Můj projekt ●4 │ ⇄ │ ⋯ │ ⤓
```

- **Živý stav:** ✳ pracuje, ● čeká na tebe, ✓ hotovo, s časem tahu a aktuálním nástrojem.
- **Schvalování z Touch Baru:** Povolit / Zamítnout bez přepnutí do Clauda.
- **Karty:** otázky, box dalšího kroku a nabídky nové session se odklikávají přímo na Touch Baru, i když jsi v jiné aplikaci.
- **Útrata:** tokeny a orientační cena za sezení, 5 h, den, týden a měsíc, tempo $/h, graf a denní rozpočet.
- **Ovládání:** režim oprávnění, model a úsilí, přepínání sezení, Zastavit, Nové, Zkomprimovat a tlačítko Commit + push.
- **Vlastní rozložení:** v okně aplikace si vybereš a přetažením seřadíš položky ve třech rozloženích.

## Požadavky

- MacBook Pro s Touch Barem, macOS 14 nebo novější
- Desktopová aplikace [Claude](https://claude.ai/download), záložka Code (Claude Code)
- Xcode Command Line Tools (`xcode-select --install`) kvůli sestavení

## Instalace

```bash
git clone https://github.com/Aodake/claude-touch-bar.git
cd claude-touch-bar
./install.sh
```

Skript aplikaci sestaví, zkopíruje do `~/Applications`, zapne spouštění po přihlášení a otevře okno.

Pak:

1. **Zapni hooky** v okně (Napojení na Claude → Zapnout). Díky nim je stav přesný a jde schvalovat a odpovídat z Touch Baru.
2. **Povol Zpřístupnění** (Nastavení systému → Soukromí a zabezpečení → Zpřístupnění). Je potřeba pro ovládání okna Clauda.
3. *Volitelně:* vytvoř si podpisový certifikát **ClaudeTouchBar Local** (Přístup ke klíčence → Asistent pro certifikáty → Vytvořit certifikát, typ *Podepisování kódu*). `build.sh` jím aplikaci podepíše, takže oprávnění Zpřístupnění přežije nové verze. Bez certifikátu se podepisuje ad-hoc a oprávnění je po každém sestavení potřeba dát znovu.

## Jak se chová

- **V Claudovi** se bar ukáže sám a zabírá celý Touch Bar. **⤓** ho zmenší zpět na Touch Bar Macu.
- **Mimo Claude** zůstává v Control Stripu ikona **✳**. Ťuknutím ukážeš Claude bar v kompaktní velikosti vedle jasu a hlasitosti.
- **⌃⌥C** (Control + Option + C) ukáže nebo schová Claude bar odkudkoliv.
- Schválení a karty s otázkami tě následují i do jiné aplikace, dokud na ně neodpovíš.
- Když Claude dokončí práci a ty jsi jinde, vyskočí `✓ Hotovo: <sezení> │ Otevřít`, zazní zvuk a ✳ bliká.

## Okno aplikace

Otevřeš ho z Launchpadu nebo Spotlightu („Claude Touch Bar“), případně ťuknutím na číslo na Touch Baru. Po zavření okna aplikace dál běží na pozadí.

- **Přehled:** stav, schválení, kontext, postup plánu, útrata (sezení / 5 h / dnes / týden / měsíc), tempo $/h, aktivní čas, grafy za 24 h a 30 dní, denní rozpočet s odhadem výdrže, změněné soubory.
- **Touch Bar:** editor tří rozložení (Kompaktní, Přehled, Minimal). Položky zapneš, vypneš a přetažením seřadíš. ⇄ mezi rozloženími přepíná přímo na Touch Baru.
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
| Změněné soubory | kolik souborů Claude v sezení upravil (seznam je v okně) |
| Čekající sezení | `● 2 čeká`; ťuknutím skočíš na první |
| Commit a push | `↑ Můj projekt ●4 ↑1`; pošle do otevřeného chatu „Commitni a pushni změny“ |
| Přepínač modelu | Opus / Fable / Sonnet / Haiku a „Úsilí ▸“ (každý stisk posune úsilí o úroveň) |
| ⋯ | Povolit / Zamítnout, Zastavit, Nové, Push, režim oprávnění, model, sezení, detail |

## Hooky Claude Code

Hooky se zapnou v okně nebo příkazem:

```bash
"$HOME/Applications/Claude Touch Bar.app/Contents/MacOS/ClaudeTouchBar" --install-hooks
```

Přidají se do `~/.claude/settings.json`. Ostatní hooky zůstanou a záloha se uloží do `settings.json.bak-claudetouchbar`. Hooky posílají události aplikaci přes lokální unixový socket. Žádost o povolení čeká na odpověď z Touch Baru, nebo na odpověď přímo v Claudovi, podle toho, co přijde dřív. V režimu *Auto* se Claude na povolení neptá, takže schvalovací bar nevyskočí. Události se zapisují do `~/Library/Application Support/ClaudeTouchBar/hooks.log`.

## Odkud jsou data a co stojí

Code tab zapisuje přepisy sezení do `~/.claude/projects/**.jsonl` a aplikace je jen čte. Nic neposílá po síti a nesahá na přihlašovací údaje. Chat tab tokeny lokálně neukládá, takže se nepočítá.

Cena v $ je **orientační přepočet podle veřejného API ceníku** (vstup, výstup, zápis a čtení z cache, podle modelu). U předplatného (Pro, Max, Team, Enterprise) se po tokenech neplatí. Číslo ukazuje, kolik by stejná práce stála přes API. Ceník je v `Sources/Pricing.swift`.

## Užitečné příkazy

```bash
# Co by Touch Bar ukázal, bez Touch Baru
"$HOME/Applications/Claude Touch Bar.app/Contents/MacOS/ClaudeTouchBar" --dump
```

## Odinstalace

```bash
"$HOME/Applications/Claude Touch Bar.app/Contents/MacOS/ClaudeTouchBar" --uninstall-hooks; pkill -x ClaudeTouchBar; rm -f ~/Library/LaunchAgents/local.ClaudeTouchBar.plist; rm -rf "$HOME/Applications/Claude Touch Bar.app"
```

## Struktura

| Soubor | Obsah |
|---|---|
| `Sources/TouchBarController.swift` | sestavení a vykreslení Touch Baru |
| `Sources/AppDelegate.swift` | propojení všeho, upozornění, zkratka ⌃⌥C |
| `Sources/UsageStore.swift` | čtení přepisů, tokeny, útrata, stav sezení |
| `Sources/Hooks.swift` | hook server a klient, instalace hooků |
| `Sources/ClaudeUI.swift` | ovládání okna Clauda přes Zpřístupnění, karty |
| `Sources/DetailWindow.swift` | okno aplikace (SwiftUI) |
| `Sources/BarItems.swift` | položky a rozložení |
| `Sources/SystemTouchBar.swift` | neveřejné API Touch Baru |
| `Sources/Pricing.swift` | ceník modelů |

## Technická poznámka

Zobrazení nad jinými aplikacemi a ikona v Control Stripu používají neveřejné API Touch Baru (stejně jako MTMR nebo Pock). Ovládání okna Clauda jde přes rozhraní Zpřístupnění. Kdyby budoucí macOS nebo nová verze Clauda něco z toho změnila, aplikace nespadne, jen daná funkce přestane fungovat.

Neoficiální projekt, není spojený s Anthropicem.

## Podpora

Jestli ti aplikace ušetří pár přepínání oken a chceš poděkovat, můžeš mi [poslat na kafe přes PayPal](https://paypal.me/aodake). Úplně dobrovolně.

## Licence

[MIT](LICENSE)
