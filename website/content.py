# The words on the Snapfly website, in English, German and Arabic.
# Labels the app itself shows (menu items, settings, line styles) are not
# here: build.py reads them from the app's Localizable.strings, so the site
# always says what the app says.

SITE_URL = "https://mgrd281.github.io/Screenshots/"
DOWNLOAD = "https://github.com/mgrd281/Screenshots/releases/download/latest/Snapfly.zip"
REPO = "https://github.com/mgrd281/Screenshots"
EMAIL = "mgrdegh@gmx.de"
MAKER = "Mgrdegh Ghazarian"

# Code, folder, name in the language menu.
LANGS = [("en", "", "English"), ("de", "de/", "Deutsch"), ("ar", "ar/", "العربية")]

TEXT = {}

TEXT["en"] = dict(
    dir="ltr",
    title_home="Snapfly: screenshots, one click from any chat",
    desc_home="Snapfly hangs every screenshot on a line at the top of your Mac's screen, ready to copy or send into any chat, with private details covered. Free for macOS 14 or later.",
    title_privacy="Privacy Policy · Snapfly",
    desc_privacy="Snapfly collects no data. It runs entirely on your Mac and never connects to the internet.",
    title_support="Support · Snapfly",
    desc_support="Help with Snapfly, the screenshot line for the Mac, and how to reach us.",
    skip="Skip to content",
    nav_features="Features",
    nav_privacy="Privacy",
    nav_support="Support",
    lang_label="Language",
    menu_label="Snapfly",

    hero_sub="Every screenshot you take hangs on a line at the top of your screen. Click one to copy it, or send it straight into the chat you’re typing in. Names and other private details are covered first, whether it goes to ChatGPT or to a person.",
    cta="Download for Mac",
    cta_note="Free · macOS 14 or later · Apple silicon and Intel",
    try_hint="Try it: click a screenshot, or its paper plane.",
    chat_title="Chat",
    chat_in="Can you send me yesterday’s invoice?",
    chat_reply="Got it, thanks!",
    chat_placeholder="Message",
    chat_label="A chat window, the app in front",
    send_label="Send to chat",
    card_names=["Invoice", "Map", "Sales chart", "Calendar", "Sunset photo"],
    line_label="Screenshots hanging on Snapfly’s line",
    refill="New screenshots",

    send_h="From the line into the chat.",
    send_p="Every screenshot carries a paper plane. Click it, and Snapfly pastes the screenshot into the app in front, a chat, ChatGPT or an email, right where you were typing. <span class='chord'><kbd>⌃</kbd><kbd>⌥</kbd><kbd>V</kbd></span> sends the newest one without reaching for the mouse. Once sent, it leaves the line, so the line only holds what’s still to send.",
    keys=["control", "option", ""],
    keys_label="The shortcut Control, Option, V",

    desk_h="Your Desktop, finally clear.",
    desk_p="Let Snapfly handle your screenshots and they skip the Desktop. No floating thumbnail, no five-second wait: each one hangs the instant you take it. Drag one into a folder to keep it. Everything else lets go when you’re done.",
    desk_file="Screenshot 2026-10-15 at 09.{m}.{s}",
    desk_label="A Desktop covered in screenshot files, which fly up onto the line",
    replay="Play again",

    priv_h="Private details stay private.",
    priv_p="Before a screenshot goes to ChatGPT, another AI or a person, Snapfly covers what you choose: names, addresses, emails, phone numbers, bank cards and accounts, health details. Whatever leaves the line, copied, sent or dragged out, leaves covered. Snapfly reads the text on your Mac, and the screenshot file itself never changes.",
    example="Example",
    inv=dict(title="Invoice 2026-1042", date="October 14, 2026", bill="Billing address",
             name="Lena Hoffmann", street="Lindenstraße 12", city="10969 Berlin",
             email="lena.hoffmann@example.com", phone="+49 30 1234 5678",
             items=[("Desk lamp", "1 × 49.00 €"), ("Cable set", "2 × 12.50 €")],
             total="Total", total_v="74.00 €", pay="Paid by bank transfer",
             iban="IBAN DE89 3704 0044 0532 0130 00"),

    menu_h="Hold a screenshot. The rest is right there.",
    menu_p="Press and hold any screenshot, or right-click it, for everything else it can do.",
    menu_hint="Point at an item to see what it does.",
    chat_app="Chat",
    menu_desc={
        "Copy": "Copies the screenshot, private details covered, ready for ⌘V anywhere.",
        "Copy Text": "Copies the words in it, read on your Mac, private details left out.",
        "Paste into %@": "Pastes it straight into the app in front, where you were typing.",
        "Make PDF": "Puts this screenshot, or all the ones you picked, in one PDF, a page each.",
        "Combine into one image": "Joins the screenshots you picked into one image, one under another or side by side.",
        "Pin": "Keeps it on the line when everything else is taken down.",
        "Translate Text": "Translates its text into your language with Apple’s translation, on your Mac. macOS 15 or later.",
        "Describe": "Writes a line about what it shows with Apple Intelligence, on your Mac, ready to send along.",
        "Quick Look": "A quick look at full size.",
        "Markup": "Draw, write, crop or sign on it.",
        "Hide Part…": "Drag a box over anything the covering missed. It stays hidden in whatever leaves the line.",
        "Show in Finder": "Shows the file where it’s saved.",
        "Discard": "Lets it go.",
    },

    styles_h="Four ways to hang.",
    styles_p="Pick what your screenshots hang on. Everything else works the same on each.",
    styles={
        "Clothesline": "Crooked photos swaying on clips.",
        "Glass shelf": "Upright on a shelf of Liquid Glass, like the Dock.",
        "Island": "Black, hanging from the top of the screen like the notch grown wide.",
        "Card stack": "A stack by the right edge that spreads out as you reach it, with a count on top.",
    },

    design_h="Nothing leaves your Mac.",
    design_points=["No account.", "No network.", "No analytics."],
    design_p="Reading text, covering details, translating and describing all happen on your Mac, with Apple’s own frameworks. Snapfly never connects to the internet.",
    design_link="Read the privacy policy",

    close_h="Hang your first screenshot.",
    close_note="Free · macOS 14 or later · Apple silicon and Intel · 13 languages · Signed and notarized by Apple",

    footer_made=f"Made by {MAKER}.",
    footer_based="Based on Tendedero by Alejandro Buján, under the MIT License.",
    footer_tm="Mac and macOS are trademarks of Apple Inc.",
    footer_source="Source code",
    footer_contact="Contact",

    updated_label="Last updated",
    updated="October 15, 2026",

    privacy_title="Privacy Policy",
    privacy_short_h="In short",
    privacy_short="Snapfly collects no personal data. It works entirely on your Mac and never connects to the internet. This website sets no cookies and uses no analytics.",
    privacy=[
        ("Who is responsible",
         f"""<p>Snapfly is made by {MAKER}. For any question about privacy, write to <a href="mailto:{EMAIL}">{EMAIL}</a>.</p>"""),
        ("The Snapfly app",
         """<ul>
<li><strong>No data is collected.</strong> Snapfly has no account, no analytics, no advertising and no tracking. It does not send your screenshots, their text or anything about you to us or to anyone else.</li>
<li><strong>No network.</strong> The app never connects to the internet. Reading the text in a screenshot, covering private details, searching, translating and describing all run on your Mac, with Apple’s frameworks.</li>
<li><strong>Your files.</strong> Snapfly reads the screenshots in the folders you let it watch, and in the Mac App Store edition the Snapfly folder in Pictures. It copies, sends, moves or deletes a screenshot only when you ask it to, or, if you leave that setting on, after you have sent it into a chat.</li>
<li><strong>Copied images.</strong> If you turn on Hang copied images, Snapfly looks at images you copy, to hang them on the line. It leaves alone anything copied together with text or a file, and anything a password manager marks as private.</li>
<li><strong>The Accessibility permission</strong> lets the send button paste a screenshot into the app you are using, by pressing ⌘V there. Snapfly uses it for nothing else. You can turn it off at any time in System Settings › Privacy &amp; Security › Accessibility.</li>
<li><strong>Your settings</strong>, such as the line style and what to cover, are stored on your Mac only.</li>
</ul>"""),
        ("Apple’s services",
         """<p>Translate Text uses Apple’s translation on your Mac; macOS may download language files from Apple for it. Describe uses Apple Intelligence on your Mac. When you get Snapfly from the Mac App Store or TestFlight, Apple handles that under its own privacy policy. If you have agreed to share analytics with app developers, Apple may give us anonymous crash reports and usage statistics, which we use only to fix problems. See <a href="https://www.apple.com/legal/privacy/">Apple’s privacy policy</a>.</p>"""),
        ("This website",
         """<p>This website is hosted on GitHub Pages, a service of GitHub, Inc. in the United States. When you visit it, GitHub’s servers receive technical data such as your IP address and browser, and GitHub logs it to keep the service secure. We have no access to those logs. The legal basis is our legitimate interest in offering this website securely (Art. 6(1)(f) GDPR). See the <a href="https://docs.github.com/site-policy/privacy-policies/github-general-privacy-statement">GitHub Privacy Statement</a>.</p>
<p>The website sets no cookies, loads nothing from other services and uses no analytics. If you pick a language, your browser remembers it in its local storage. That never leaves your device.</p>"""),
        ("Email",
         """<p>If you write to us, we use your email address and your message only to answer you, and delete them once they are no longer needed (Art. 6(1)(b) and (f) GDPR).</p>"""),
        ("Children",
         """<p>Snapfly collects no data from anyone, children included.</p>"""),
        ("Your rights",
         """<p>Under the GDPR you have the right to access, correct and delete your data, to restrict or object to its processing, and to data portability. You may also complain to a data protection supervisory authority. As Snapfly holds no data about you, these will rarely apply, but you can write to us at any time.</p>"""),
        ("Changes",
         """<p>If this policy changes, we update this page and the date at the top.</p>"""),
    ],

    support_title="Support",
    support_intro="Questions, problems or ideas? Write to us in English, German or Arabic.",
    support_mail="Email us",
    support_subject="Snapfly",
    faq_h="Questions and answers",
    faq=[
        ("How do I install Snapfly?",
         """<p>Download Snapfly.zip, open it and drag Snapfly into your Applications folder. It is signed and notarized by Apple, so it opens like any other app. Snapfly lives in the menu bar and has no Dock icon.</p>"""),
        ("How do my screenshots get onto the line?",
         """<p>The first time Snapfly opens, it offers to handle your screenshots. Choose Turn on, and every screenshot you take hangs on the line instead of landing on your Desktop. You can change it any time with Handle screenshots in Snapfly’s menu in the menu bar.</p>
<p>In the Mac App Store edition, open the Screenshot app, click Options, choose Other Location and pick the Snapfly folder in Pictures.</p>"""),
        ("How do I bring the line down?",
         """<p>Rest the pointer at the top edge of the screen, in the menu bar, and the line glides down. Or press <span class='chord'><kbd>⌃</kbd><kbd>⌥</kbd><kbd>T</kbd></span>. Move away and it tucks itself away again.</p>"""),
        ("How do I send a screenshot into a chat?",
         """<p>Click into the chat’s message field, then click the paper plane on a screenshot. Or press <span class='chord'><kbd>⌃</kbd><kbd>⌥</kbd><kbd>V</kbd></span> to send the newest one. To send several at once, ⌘-click them first.</p>"""),
        ("The send button says “Not allowed yet”.",
         """<p>Sending presses ⌘V for you, and macOS asks for the Accessibility permission for that.</p>
<ol>
<li>Open System Settings › Privacy &amp; Security › Accessibility.</li>
<li>If Snapfly is in the list, switch it on.</li>
<li>If it isn’t, click +, choose Snapfly in Applications, click Open and switch it on.</li>
<li>Quit Snapfly and open it again.</li>
</ol>"""),
        ("How do I make a PDF?",
         """<p>Press and hold a screenshot, or right-click it, and choose Make PDF. To put several screenshots in one PDF, ⌘-click them first, then click the PDF button on the tag at the end of the line.</p>"""),
        ("How do I cover private details?",
         """<p>Open Settings › Privacy and check what to cover. To cover anything it missed, hold the screenshot and choose Hide Part…</p>"""),
        ("Which Macs does Snapfly run on?",
         """<p>macOS 14 Sonoma or later, on Apple silicon and Intel. Translate Text needs macOS 15. Describe writes with Apple Intelligence where your Mac has it, and uses the screenshot’s title otherwise.</p>"""),
        ("How do I uninstall Snapfly?",
         """<p>Quit it from its menu in the menu bar, then drag Snapfly from Applications to the Trash. Screenshots you kept stay where you saved them.</p>"""),
        ("Something else isn’t working.",
         f"""<p>Write to <a href="mailto:{EMAIL}">{EMAIL}</a> with your macOS version and what happened. A screenshot helps. You can also <a href="{REPO}/issues">open an issue on GitHub</a>.</p>"""),
    ],

    notfound_title="Page not found",
    notfound_p="This page isn’t on the line.",
    notfound_link="Go to the home page",
)

TEXT["de"] = dict(
    dir="ltr",
    title_home="Snapfly: Bildschirmfotos, einen Klick von jedem Chat entfernt",
    desc_home="Snapfly hängt jedes Bildschirmfoto an eine Leine oben auf dem Bildschirm deines Mac – bereit zum Kopieren oder Senden in jeden Chat, private Angaben verdeckt. Kostenlos ab macOS 14.",
    title_privacy="Datenschutzerklärung · Snapfly",
    desc_privacy="Snapfly erhebt keine Daten. Die App läuft vollständig auf deinem Mac und verbindet sich nie mit dem Internet.",
    title_support="Support · Snapfly",
    desc_support="Hilfe zu Snapfly, der Leine für Bildschirmfotos auf dem Mac, und wie du uns erreichst.",
    skip="Zum Inhalt springen",
    nav_features="Funktionen",
    nav_privacy="Datenschutz",
    nav_support="Support",
    lang_label="Sprache",
    menu_label="Snapfly",

    hero_sub="Jedes Bildschirmfoto hängt an einer Leine oben auf deinem Bildschirm. Ein Klick kopiert es, oder du schickst es direkt in den Chat, in dem du gerade schreibst. Namen und andere private Angaben werden vorher verdeckt, ob es an ChatGPT geht oder an einen Menschen.",
    cta="Für Mac laden",
    cta_note="Kostenlos · ab macOS 14 · Apple Silicon und Intel",
    try_hint="Probier’s aus: Klick auf ein Bild oder auf seinen Papierflieger.",
    chat_title="Chat",
    chat_in="Kannst du mir die Rechnung von gestern schicken?",
    chat_reply="Ist angekommen, danke!",
    chat_placeholder="Nachricht",
    chat_label="Ein Chatfenster, die App im Vordergrund",
    send_label="In den Chat senden",
    card_names=["Rechnung", "Karte", "Umsatzdiagramm", "Kalender", "Foto vom Sonnenuntergang"],
    line_label="Bildschirmfotos an der Leine von Snapfly",
    refill="Neue Bildschirmfotos",

    send_h="Von der Leine direkt in den Chat.",
    send_p="Jedes Bildschirmfoto hat einen Papierflieger. Klick darauf, und Snapfly setzt es in die App im Vordergrund ein – einen Chat, ChatGPT oder eine E-Mail –, genau dort, wo du gerade schreibst. <span class='chord'><kbd>⌃</kbd><kbd>⌥</kbd><kbd>V</kbd></span> schickt das neueste, ohne dass du zur Maus greifst. Was gesendet ist, verlässt die Leine. So hängt dort nur, was noch zu senden ist.",
    keys=["ctrl", "alt", ""],
    keys_label="Das Kürzel Control, Option, V",

    desk_h="Endlich ein aufgeräumter Schreibtisch.",
    desk_p="Überlass Snapfly deine Bildschirmfotos, und sie landen nicht mehr auf dem Schreibtisch. Keine schwebende Vorschau, keine fünf Sekunden Warten: Jedes hängt sofort an der Leine. Zieh eines in einen Ordner, um es zu behalten. Alles andere verschwindet, wenn du fertig bist.",
    desk_file="Bildschirmfoto 2026-10-15 um 09.{m}.{s}",
    desk_label="Ein Schreibtisch voller Bildschirmfotos, die nach oben an die Leine fliegen",
    replay="Noch mal abspielen",

    priv_h="Private Angaben bleiben privat.",
    priv_p="Bevor ein Bildschirmfoto an ChatGPT, eine andere KI oder einen Menschen geht, verdeckt Snapfly, was du wählst: Namen, Adressen, E-Mails, Telefonnummern, Bankkarten und Konten, Gesundheitsdaten. Was die Leine verlässt – kopiert, gesendet oder herausgezogen –, ist verdeckt. Snapfly liest den Text auf deinem Mac, und die Bilddatei selbst bleibt unverändert.",
    example="Beispiel",
    inv=dict(title="Rechnung 2026-1042", date="14. Oktober 2026", bill="Rechnungsadresse",
             name="Lena Hoffmann", street="Lindenstraße 12", city="10969 Berlin",
             email="lena.hoffmann@example.com", phone="+49 30 1234 5678",
             items=[("Schreibtischlampe", "1 × 49,00 €"), ("Kabelset", "2 × 12,50 €")],
             total="Gesamt", total_v="74,00 €", pay="Bezahlt per Überweisung",
             iban="IBAN DE89 3704 0044 0532 0130 00"),

    menu_h="Halt ein Bild gedrückt. Alles andere ist gleich da.",
    menu_p="Halt ein Bildschirmfoto gedrückt oder klick mit rechts darauf – dann siehst du alles, was es noch kann.",
    menu_hint="Zeig auf einen Eintrag, um zu sehen, was er macht.",
    chat_app="Chat",
    menu_desc={
        "Copy": "Kopiert das Bildschirmfoto, private Angaben verdeckt, bereit für ⌘V überall.",
        "Copy Text": "Kopiert die Wörter darin, gelesen auf deinem Mac, private Angaben ausgelassen.",
        "Paste into %@": "Setzt es direkt in die App im Vordergrund ein, dort, wo du gerade schreibst.",
        "Make PDF": "Legt dieses Bildschirmfoto oder alle ausgewählten in ein PDF, jedes auf eine Seite.",
        "Combine into one image": "Fügt die ausgewählten Bildschirmfotos zu einem Bild zusammen, untereinander oder nebeneinander.",
        "Pin": "Hält es an der Leine, wenn alles andere abgenommen wird.",
        "Translate Text": "Übersetzt den Text mit Apples Übersetzung in deine Sprache, auf deinem Mac. Ab macOS 15.",
        "Describe": "Schreibt mit Apple Intelligence eine Zeile dazu, was es zeigt, auf deinem Mac, bereit zum Mitsenden.",
        "Quick Look": "Ein schneller Blick in voller Größe.",
        "Markup": "Zeichnen, schreiben, zuschneiden oder unterschreiben.",
        "Hide Part…": "Zieh ein Rechteck über alles, was nicht verdeckt wurde. Es bleibt verborgen, was immer die Leine verlässt.",
        "Show in Finder": "Zeigt die Datei dort, wo sie gespeichert ist.",
        "Discard": "Lässt es los.",
    },

    styles_h="Vier Arten zu hängen.",
    styles_p="Wähle, woran deine Bildschirmfotos hängen. Alles andere funktioniert überall gleich.",
    styles={
        "Clothesline": "Schiefe Bilder, die an Klammern schaukeln.",
        "Glass shelf": "Aufrecht auf einem Regal aus Liquid Glass, wie das Dock.",
        "Island": "Schwarz, von oben herab, wie eine breit gewordene Notch.",
        "Card stack": "Ein Stapel am rechten Rand, der sich auffächert, wenn du hingehst, mit der Anzahl obendrauf.",
    },

    design_h="Nichts verlässt deinen Mac.",
    design_points=["Kein Konto.", "Kein Netzwerk.", "Keine Analyse."],
    design_p="Text lesen, Angaben verdecken, übersetzen und beschreiben: Das alles passiert auf deinem Mac, mit Apples eigenen Frameworks. Snapfly verbindet sich nie mit dem Internet.",
    design_link="Datenschutzerklärung lesen",

    close_h="Häng dein erstes Bildschirmfoto auf.",
    close_note="Kostenlos · ab macOS 14 · Apple Silicon und Intel · 13 Sprachen · Von Apple signiert und beglaubigt",

    footer_made=f"Gemacht von {MAKER}.",
    footer_based="Basiert auf Tendedero von Alejandro Buján, unter der MIT-Lizenz.",
    footer_tm="Mac und macOS sind Marken der Apple Inc.",
    footer_source="Quellcode",
    footer_contact="Kontakt",

    updated_label="Stand",
    updated="15. Oktober 2026",

    privacy_title="Datenschutzerklärung",
    privacy_short_h="Kurz gesagt",
    privacy_short="Snapfly erhebt keine personenbezogenen Daten. Die App arbeitet vollständig auf deinem Mac und verbindet sich nie mit dem Internet. Diese Website setzt keine Cookies und nutzt keine Analyse.",
    privacy=[
        ("Verantwortlich",
         f"""<p>Snapfly wird von {MAKER} entwickelt. Bei Fragen zum Datenschutz schreib an <a href="mailto:{EMAIL}">{EMAIL}</a>.</p>"""),
        ("Die App Snapfly",
         """<ul>
<li><strong>Es werden keine Daten erhoben.</strong> Snapfly hat kein Konto, keine Analyse, keine Werbung und kein Tracking. Die App sendet weder deine Bildschirmfotos noch deren Text noch irgendetwas über dich an uns oder an Dritte.</li>
<li><strong>Kein Netzwerk.</strong> Die App verbindet sich nie mit dem Internet. Texterkennung, das Verdecken privater Angaben, die Suche, das Übersetzen und Beschreiben laufen auf deinem Mac, mit Apples Frameworks.</li>
<li><strong>Deine Dateien.</strong> Snapfly liest die Bildschirmfotos in den Ordnern, die du freigibst, in der Mac App Store-Ausgabe außerdem den Ordner „Snapfly“ in „Bilder“. Die App kopiert, sendet, verschiebt oder löscht ein Bildschirmfoto nur, wenn du es willst, oder – wenn du die Einstellung eingeschaltet lässt – nachdem du es in einen Chat gesendet hast.</li>
<li><strong>Kopierte Bilder.</strong> Wenn du „Kopierte Bilder aufhängen“ einschaltest, sieht sich Snapfly Bilder an, die du kopierst, um sie an die Leine zu hängen. Was zusammen mit Text oder einer Datei kopiert wurde und was ein Passwortmanager als privat markiert, bleibt unberührt.</li>
<li><strong>Die Berechtigung für Bedienungshilfen</strong> erlaubt der Senden-Taste, ein Bildschirmfoto in die App einzusetzen, die du gerade benutzt, indem sie dort ⌘V drückt. Snapfly nutzt sie für nichts anderes. Du kannst sie jederzeit unter Systemeinstellungen › Datenschutz &amp; Sicherheit › Bedienungshilfen ausschalten.</li>
<li><strong>Deine Einstellungen</strong>, etwa der Stil der Leine und was verdeckt wird, werden nur auf deinem Mac gespeichert.</li>
</ul>"""),
        ("Dienste von Apple",
         """<p>„Text übersetzen“ nutzt Apples Übersetzung auf deinem Mac; macOS lädt dafür eventuell Sprachdateien von Apple. „Beschreiben“ nutzt Apple Intelligence auf deinem Mac. Wenn du Snapfly aus dem Mac App Store oder über TestFlight lädst, verarbeitet Apple das nach seiner eigenen Datenschutzrichtlinie. Wenn du zugestimmt hast, Analysedaten mit App-Entwicklern zu teilen, kann Apple uns anonyme Absturzberichte und Nutzungsstatistiken geben, die wir nur zur Fehlerbehebung verwenden. Siehe die <a href="https://www.apple.com/de/legal/privacy/">Datenschutzrichtlinie von Apple</a>.</p>"""),
        ("Diese Website",
         """<p>Diese Website wird bei GitHub Pages gehostet, einem Dienst der GitHub, Inc. in den USA. Beim Besuch erhalten die Server von GitHub technische Daten wie deine IP-Adresse und deinen Browser, und GitHub protokolliert sie, um den Dienst sicher zu betreiben. Wir haben keinen Zugriff auf diese Protokolle. Rechtsgrundlage ist unser berechtigtes Interesse, diese Website sicher anzubieten (Art. 6 Abs. 1 lit. f DSGVO). Siehe das <a href="https://docs.github.com/de/site-policy/privacy-policies/github-general-privacy-statement">Datenschutz-Statement von GitHub</a>.</p>
<p>Die Website setzt keine Cookies, lädt nichts von anderen Diensten und nutzt keine Analyse. Wenn du eine Sprache wählst, merkt sich dein Browser das in seinem lokalen Speicher. Das verlässt dein Gerät nie.</p>"""),
        ("E-Mail",
         """<p>Wenn du uns schreibst, nutzen wir deine E-Mail-Adresse und deine Nachricht nur, um dir zu antworten, und löschen sie, sobald sie nicht mehr gebraucht werden (Art. 6 Abs. 1 lit. b und f DSGVO).</p>"""),
        ("Kinder",
         """<p>Snapfly erhebt von niemandem Daten, auch nicht von Kindern.</p>"""),
        ("Deine Rechte",
         """<p>Nach der DSGVO hast du das Recht auf Auskunft, Berichtigung und Löschung deiner Daten, auf Einschränkung der Verarbeitung, auf Widerspruch und auf Datenübertragbarkeit. Außerdem kannst du dich bei einer Datenschutz-Aufsichtsbehörde beschweren. Da Snapfly keine Daten über dich hat, betrifft dich das selten, aber du kannst uns jederzeit schreiben.</p>"""),
        ("Änderungen",
         """<p>Wenn sich diese Erklärung ändert, aktualisieren wir diese Seite und das Datum oben.</p>"""),
    ],

    support_title="Support",
    support_intro="Fragen, Probleme oder Ideen? Schreib uns auf Deutsch, Englisch oder Arabisch.",
    support_mail="E-Mail schreiben",
    support_subject="Snapfly",
    faq_h="Fragen und Antworten",
    faq=[
        ("Wie installiere ich Snapfly?",
         """<p>Lade Snapfly.zip, öffne die Datei und zieh Snapfly in deinen Ordner „Programme“. Snapfly ist von Apple signiert und beglaubigt und öffnet sich wie jede andere App. Snapfly lebt in der Menüleiste und hat kein Symbol im Dock.</p>"""),
        ("Wie kommen meine Bildschirmfotos an die Leine?",
         """<p>Beim ersten Öffnen bietet Snapfly an, deine Bildschirmfotos zu übernehmen. Wähl „Einschalten“, und jedes Bildschirmfoto hängt an der Leine statt auf deinem Schreibtisch. Du kannst das jederzeit mit „Bildschirmfotos übernehmen“ im Menü von Snapfly in der Menüleiste ändern.</p>
<p>In der Mac App Store-Ausgabe öffnest du die App „Bildschirmfoto“, klickst auf „Optionen“, wählst „Anderer Ort“ und dann den Ordner „Snapfly“ in „Bilder“.</p>"""),
        ("Wie hole ich die Leine herunter?",
         """<p>Lass den Zeiger am oberen Bildschirmrand in der Menüleiste ruhen, und die Leine gleitet herunter. Oder drück <span class='chord'><kbd>⌃</kbd><kbd>⌥</kbd><kbd>T</kbd></span>. Geh weg, und sie verschwindet wieder.</p>"""),
        ("Wie sende ich ein Bildschirmfoto in einen Chat?",
         """<p>Klick in das Nachrichtenfeld des Chats und dann auf den Papierflieger eines Bildschirmfotos. Oder drück <span class='chord'><kbd>⌃</kbd><kbd>⌥</kbd><kbd>V</kbd></span>, um das neueste zu senden. Um mehrere auf einmal zu senden, klick sie vorher mit ⌘ an.</p>"""),
        ("Die Senden-Taste zeigt „Noch nicht erlaubt“.",
         """<p>Beim Senden drückt Snapfly für dich ⌘V, und dafür fragt macOS nach der Berechtigung für Bedienungshilfen.</p>
<ol>
<li>Öffne Systemeinstellungen › Datenschutz &amp; Sicherheit › Bedienungshilfen.</li>
<li>Steht Snapfly in der Liste, schalte es ein.</li>
<li>Wenn nicht, klick auf +, wähl Snapfly in „Programme“, klick auf „Öffnen“ und schalte es ein.</li>
<li>Beende Snapfly und öffne es wieder.</li>
</ol>"""),
        ("Wie erstelle ich ein PDF?",
         """<p>Halt ein Bildschirmfoto gedrückt oder klick mit rechts darauf und wähl „PDF erstellen“. Für mehrere Bildschirmfotos in einem PDF klickst du sie vorher mit ⌘ an und dann auf die PDF-Taste am Schild am Ende der Leine.</p>"""),
        ("Wie verdecke ich private Angaben?",
         """<p>Öffne Einstellungen › Datenschutz und wähle, was verdeckt werden soll. Um etwas zu verdecken, das übersehen wurde, halt das Bildschirmfoto gedrückt und wähl „Bereich verdecken …“.</p>"""),
        ("Auf welchen Macs läuft Snapfly?",
         """<p>Ab macOS 14 Sonoma, auf Apple Silicon und Intel. „Text übersetzen“ braucht macOS 15. „Beschreiben“ schreibt mit Apple Intelligence, wenn dein Mac es hat, und nimmt sonst den Titel des Bildschirmfotos.</p>"""),
        ("Wie deinstalliere ich Snapfly?",
         """<p>Beende Snapfly über sein Menü in der Menüleiste und zieh es dann aus „Programme“ in den Papierkorb. Bildschirmfotos, die du behalten hast, bleiben, wo du sie gespeichert hast.</p>"""),
        ("Etwas anderes funktioniert nicht.",
         f"""<p>Schreib an <a href="mailto:{EMAIL}">{EMAIL}</a> mit deiner macOS-Version und was passiert ist. Ein Bildschirmfoto hilft. Du kannst auch <a href="{REPO}/issues">ein Issue auf GitHub öffnen</a>.</p>"""),
    ],

    notfound_title="Seite nicht gefunden",
    notfound_p="Diese Seite hängt nicht an der Leine.",
    notfound_link="Zur Startseite",
)

TEXT["ar"] = dict(
    dir="rtl",
    title_home="Snapfly: لقطات الشاشة، على بُعد نقرة من أي دردشة",
    desc_home="يعلّق Snapfly كل لقطة شاشة على حبل في أعلى شاشة جهاز Mac، جاهزة للنسخ أو الإرسال إلى أي دردشة، والمعلومات الخاصة مغطّاة. مجاني لنظام macOS 14 أو أحدث.",
    title_privacy="سياسة الخصوصية · Snapfly",
    desc_privacy="لا يجمع Snapfly أي بيانات. يعمل بالكامل على جهاز Mac ولا يتصل بالإنترنت أبدًا.",
    title_support="الدعم · Snapfly",
    desc_support="مساعدة في استخدام Snapfly، حبل لقطات الشاشة على Mac، وطريقة التواصل معنا.",
    skip="انتقل إلى المحتوى",
    nav_features="المزايا",
    nav_privacy="الخصوصية",
    nav_support="الدعم",
    lang_label="اللغة",
    menu_label="Snapfly",

    hero_sub="كل لقطة شاشة تلتقطها تُعلَّق على حبل في أعلى شاشتك. انقرها لتنسخها، أو أرسلها مباشرة إلى الدردشة التي تكتب فيها. والأسماء وغيرها من المعلومات الخاصة تُغطّى قبل الإرسال، سواء ذهبت إلى ChatGPT أو إلى شخص.",
    cta="تنزيل لجهاز Mac",
    cta_note="مجاني · macOS 14 أو أحدث · Apple silicon و Intel",
    try_hint="جرّبه: انقر لقطة، أو طائرتها الورقية.",
    chat_title="دردشة",
    chat_in="ممكن ترسل لي فاتورة أمس؟",
    chat_reply="وصلت، شكرًا!",
    chat_placeholder="رسالة",
    chat_label="نافذة دردشة، التطبيق الذي أمامك",
    send_label="إرسال إلى الدردشة",
    card_names=["فاتورة", "خريطة", "رسم بياني للمبيعات", "تقويم", "صورة غروب"],
    line_label="لقطات شاشة معلّقة على حبل Snapfly",
    refill="لقطات جديدة",

    send_h="من الحبل إلى الدردشة مباشرة.",
    send_p="على كل لقطة طائرة ورقية. انقرها فيلصق Snapfly اللقطة في التطبيق الذي أمامك، دردشة أو ChatGPT أو بريد إلكتروني، في المكان الذي تكتب فيه. واختصار <bdi class=\"chord\" dir=\"ltr\"><kbd>⌃</kbd><kbd>⌥</kbd><kbd>V</kbd></bdi> يرسل أحدث لقطة دون أن تلمس الفأرة. وما يُرسَل يغادر الحبل، فلا يبقى عليه إلا ما لم يُرسَل بعد.",
    keys=["control", "option", ""],
    keys_label="الاختصار Control و Option و V",

    desk_h="سطح مكتب نظيف أخيرًا.",
    desk_p="اترك لقطات الشاشة لـ Snapfly فلا تصل إلى سطح المكتب أبدًا. لا صورة مصغّرة عائمة ولا انتظار خمس ثوانٍ: كل لقطة تُعلَّق لحظة التقاطها. اسحب واحدة إلى مجلد لتحتفظ بها، والباقي يختفي حين تنتهي.",
    desk_file="لقطة شاشة 2026-10-15 في 9.{m}.{s} ص",
    desk_label="سطح مكتب مليء بملفات لقطات الشاشة، تطير إلى الحبل",
    replay="إعادة التشغيل",

    priv_h="معلوماتك الخاصة تبقى خاصة.",
    priv_p="قبل أن تذهب اللقطة إلى ChatGPT أو أي ذكاء اصطناعي آخر أو إلى شخص، يغطّي Snapfly ما تختاره: الأسماء، والعناوين، والبريد الإلكتروني، وأرقام الهواتف، والبطاقات والحسابات البنكية، والمعلومات الصحية. كل ما يغادر الحبل، نسخًا أو إرسالًا أو سحبًا، يغادره مغطّى. يقرأ Snapfly النص على جهازك، ولا يتغيّر ملف اللقطة نفسه.",
    example="مثال",
    inv=dict(title="فاتورة 2026-1042", date="14 أكتوبر 2026", bill="عنوان الفاتورة",
             name="لينا هوفمان", street="شارع ليندن 12", city="10969 برلين",
             email="lena.hoffmann@example.com", phone="+49 30 1234 5678",
             items=[("مصباح مكتب", "1 × 49,00 €"), ("مجموعة كابلات", "2 × 12,50 €")],
             total="المجموع", total_v="74,00 €", pay="دُفعت بتحويل بنكي",
             iban="IBAN DE89 3704 0044 0532 0130 00"),

    menu_h="اضغط مطوّلًا على لقطة، تجد كل شيء.",
    menu_p="اضغط مطوّلًا على أي لقطة، أو انقرها بالزر الأيمن، لترى كل ما تستطيع فعله بها.",
    menu_hint="أشر إلى أي خيار لترى ما يفعله.",
    chat_app="الدردشة",
    menu_desc={
        "Copy": "ينسخ اللقطة والمعلومات الخاصة مغطّاة، جاهزة للصق بـ ⌘V في أي مكان.",
        "Copy Text": "ينسخ الكلمات التي فيها، مقروءة على جهازك، دون المعلومات الخاصة.",
        "Paste into %@": "يلصقها مباشرة في التطبيق الذي أمامك، حيث كنت تكتب.",
        "Make PDF": "يضع هذه اللقطة، أو كل اللقطات التي اخترتها، في ملف PDF واحد، كل لقطة في صفحة.",
        "Combine into one image": "يدمج اللقطات التي اخترتها في صورة واحدة، بعضها تحت بعض أو جنبًا إلى جنب.",
        "Pin": "يُبقيها على الحبل حين يُنزَل كل شيء آخر.",
        "Translate Text": "يترجم نصها إلى لغتك بترجمة Apple، على جهازك. يحتاج macOS 15 أو أحدث.",
        "Describe": "يكتب سطرًا عمّا تُظهره بـ Apple Intelligence، على جهازك، جاهزًا للإرسال معها.",
        "Quick Look": "نظرة سريعة بالحجم الكامل.",
        "Markup": "ارسم أو اكتب أو قُصّ أو وقّع عليها.",
        "Hide Part…": "اسحب مربعًا فوق أي شيء لم تغطّه التغطية. يبقى مخفيًا في كل ما يغادر الحبل.",
        "Show in Finder": "يُظهر الملف حيث حُفظ.",
        "Discard": "يتخلّص منها.",
    },

    styles_h="أربع طرق للتعليق.",
    styles_p="اختر ما تُعلَّق عليه لقطاتك. وكل شيء آخر يعمل بالطريقة نفسها.",
    styles={
        "Clothesline": "صور مائلة تتأرجح على المشابك.",
        "Glass shelf": "صور منتصبة على رف من Liquid Glass، مثل Dock.",
        "Island": "سوداء، تتدلّى من أعلى الشاشة كأن النوتش اتّسعت.",
        "Card stack": "كومة عند حافة الشاشة تنفرد حين تقترب منها، وفوقها العدد.",
    },

    design_h="لا شيء يغادر جهازك.",
    design_points=["بلا حساب.", "بلا إنترنت.", "بلا تتبّع."],
    design_p="قراءة النص وتغطية المعلومات والترجمة والوصف، كلها تحدث على جهاز Mac الخاص بك، بأدوات Apple نفسها. لا يتصل Snapfly بالإنترنت أبدًا.",
    design_link="اقرأ سياسة الخصوصية",

    close_h="علّق أول لقطة شاشة لك.",
    close_note="مجاني · macOS 14 أو أحدث · Apple silicon و Intel · 13 لغة · موقّع ومُعتمَد من Apple",

    footer_made=f"من صنع {MAKER}.",
    footer_based="مبني على Tendedero من Alejandro Buján، بترخيص MIT.",
    footer_tm="Mac و macOS علامتان تجاريتان لشركة Apple Inc.",
    footer_source="الشيفرة المصدرية",
    footer_contact="تواصل معنا",

    updated_label="آخر تحديث",
    updated="15 أكتوبر 2026",

    privacy_title="سياسة الخصوصية",
    privacy_short_h="باختصار",
    privacy_short="لا يجمع Snapfly أي بيانات شخصية. يعمل بالكامل على جهاز Mac ولا يتصل بالإنترنت أبدًا. وهذا الموقع لا يستخدم ملفات تعريف الارتباط (الكوكيز) ولا أدوات تحليل.",
    privacy=[
        ("المسؤول",
         f"""<p>يطوّر Snapfly <bdi>{MAKER}</bdi>. لأي سؤال عن الخصوصية، راسلنا على <a href="mailto:{EMAIL}"><bdi>{EMAIL}</bdi></a>.</p>"""),
        ("تطبيق Snapfly",
         """<ul>
<li><strong>لا تُجمع أي بيانات.</strong> لا حساب في Snapfly، ولا تحليلات، ولا إعلانات، ولا تتبّع. لا يرسل التطبيق لقطاتك ولا نصوصها ولا أي شيء عنك إلينا أو إلى أي أحد.</li>
<li><strong>بلا إنترنت.</strong> لا يتصل التطبيق بالإنترنت أبدًا. قراءة النص في اللقطة، وتغطية المعلومات الخاصة، والبحث، والترجمة، والوصف، كلها تعمل على جهازك بأدوات Apple.</li>
<li><strong>ملفاتك.</strong> يقرأ Snapfly لقطات الشاشة في المجلدات التي تسمح له بمراقبتها، وفي نسخة Mac App Store مجلد Snapfly داخل «الصور». ولا ينسخ لقطة أو يرسلها أو ينقلها أو يحذفها إلا حين تطلب ذلك، أو، إن أبقيت هذا الإعداد مفعّلًا، بعد أن ترسلها إلى دردشة.</li>
<li><strong>الصور المنسوخة.</strong> إن فعّلت «تعليق الصور المنسوخة»، ينظر Snapfly إلى الصور التي تنسخها ليعلّقها على الحبل. ويترك كل ما نُسخ مع نص أو ملف، وكل ما يعلّمه مدير كلمات المرور بأنه خاص.</li>
<li><strong>إذن تسهيلات الاستخدام</strong> يسمح لزر الإرسال بلصق اللقطة في التطبيق الذي تستخدمه، بالضغط على ⌘V هناك. ولا يستخدمه Snapfly لأي شيء آخر. ويمكنك إيقافه في أي وقت من إعدادات النظام › الخصوصية والأمن › تسهيلات الاستخدام.</li>
<li><strong>إعداداتك</strong>، مثل شكل الحبل وما يُغطّى، تُحفظ على جهازك فقط.</li>
</ul>"""),
        ("خدمات Apple",
         """<p>تستخدم «ترجمة النص» ترجمة Apple على جهازك، وقد ينزّل macOS ملفات لغة من Apple لذلك. ويستخدم «وصف ذكي» Apple Intelligence على جهازك. وحين تحصل على Snapfly من Mac App Store أو TestFlight، تتولّى Apple ذلك وفق سياسة الخصوصية الخاصة بها. وإن وافقت على مشاركة التحليلات مع مطوّري التطبيقات، فقد تعطينا Apple تقارير أعطال وإحصاءات استخدام مجهولة الهوية، نستخدمها فقط لإصلاح المشكلات. انظر <a href="https://www.apple.com/legal/privacy/">سياسة خصوصية Apple</a>.</p>"""),
        ("هذا الموقع",
         """<p>هذا الموقع مستضاف على GitHub Pages، وهي خدمة من شركة GitHub, Inc. في الولايات المتحدة. حين تزوره، تتلقّى خوادم GitHub بيانات تقنية مثل عنوان IP ونوع المتصفح، وتسجّلها GitHub لحماية الخدمة. ولا نستطيع الوصول إلى هذه السجلات. والأساس القانوني هو مصلحتنا المشروعة في تقديم هذا الموقع بأمان (المادة 6(1)(f) من اللائحة العامة لحماية البيانات GDPR). انظر <a href="https://docs.github.com/site-policy/privacy-policies/github-general-privacy-statement">بيان خصوصية GitHub</a>.</p>
<p>لا يستخدم الموقع ملفات تعريف الارتباط، ولا يحمّل شيئًا من خدمات أخرى، ولا يستخدم أدوات تحليل. وإن اخترت لغة، يتذكّرها متصفحك في تخزينه المحلي، ولا يغادر ذلك جهازك أبدًا.</p>"""),
        ("البريد الإلكتروني",
         """<p>إن راسلتنا، نستخدم بريدك ورسالتك فقط للرد عليك، ونحذفهما حين لا تعود هناك حاجة إليهما (المادة 6(1)(b) و(f) من GDPR).</p>"""),
        ("الأطفال",
         """<p>لا يجمع Snapfly بيانات من أي أحد، ومن ذلك الأطفال.</p>"""),
        ("حقوقك",
         """<p>بموجب GDPR لك الحق في الاطلاع على بياناتك وتصحيحها وحذفها، وفي تقييد معالجتها أو الاعتراض عليها، وفي نقلها. ويحق لك أيضًا تقديم شكوى إلى سلطة رقابية لحماية البيانات. وبما أن Snapfly لا يحتفظ بأي بيانات عنك، فنادرًا ما ينطبق ذلك، لكن يمكنك مراسلتنا في أي وقت.</p>"""),
        ("التغييرات",
         """<p>إن تغيّرت هذه السياسة، نحدّث هذه الصفحة والتاريخ في أعلاها.</p>"""),
    ],

    support_title="الدعم",
    support_intro="أسئلة أو مشكلات أو أفكار؟ راسلنا بالعربية أو الألمانية أو الإنجليزية.",
    support_mail="راسلنا بالبريد",
    support_subject="Snapfly",
    faq_h="أسئلة وأجوبة",
    faq=[
        ("كيف أثبّت Snapfly؟",
         """<p>نزّل الملف Snapfly.zip وافتحه، ثم اسحب Snapfly إلى مجلد «التطبيقات». التطبيق موقّع ومُعتمَد من Apple، فيفتح مثل أي تطبيق آخر. يعيش Snapfly في شريط القوائم في الأعلى، وليس له أيقونة في Dock.</p>"""),
        ("كيف تصل لقطاتي إلى الحبل؟",
         """<p>عند فتح Snapfly أول مرة، يعرض أن يتولّى لقطات الشاشة. اختر «تشغيل»، فتُعلَّق كل لقطة تلتقطها على الحبل بدل أن تصل إلى سطح المكتب. ويمكنك تغيير ذلك متى شئت من «تولّي لقطات الشاشة» في قائمة Snapfly في شريط القوائم.</p>
<p>في نسخة Mac App Store، افتح تطبيق «لقطة الشاشة»، وانقر «خيارات»، واختر «موقع آخر»، ثم اختر مجلد Snapfly داخل «الصور».</p>"""),
        ("كيف أُنزل الحبل؟",
         """<p>أرِح المؤشر عند الحافة العليا للشاشة، في شريط القوائم، فينزل الحبل. أو اضغط <bdi class="chord" dir="ltr"><kbd>⌃</kbd><kbd>⌥</kbd><kbd>T</kbd></bdi>. وحين تبتعد يختفي من جديد.</p>"""),
        ("كيف أرسل لقطة إلى دردشة؟",
         """<p>انقر في خانة الكتابة في الدردشة، ثم انقر الطائرة الورقية على اللقطة. أو اضغط <bdi class="chord" dir="ltr"><kbd>⌃</kbd><kbd>⌥</kbd><kbd>V</kbd></bdi> لإرسال أحدث لقطة. ولإرسال عدة لقطات معًا، انقرها أولًا وأنت ضاغط على ⌘.</p>"""),
        ("زر الإرسال يقول «غير مسموح بعد».",
         """<p>عند الإرسال يضغط Snapfly ⌘V نيابة عنك، ولذلك يطلب macOS إذن تسهيلات الاستخدام.</p>
<ol>
<li>افتح إعدادات النظام › الخصوصية والأمن › تسهيلات الاستخدام.</li>
<li>إن كان Snapfly في القائمة، فشغّله.</li>
<li>إن لم يكن، انقر +، واختر Snapfly من «التطبيقات»، وانقر «فتح»، ثم شغّله.</li>
<li>أغلق Snapfly وافتحه من جديد.</li>
</ol>"""),
        ("كيف أصنع ملف PDF؟",
         """<p>اضغط مطوّلًا على اللقطة، أو انقرها بالزر الأيمن، واختر «إنشاء PDF». ولوضع عدة لقطات في ملف واحد، انقرها أولًا وأنت ضاغط على ⌘، ثم انقر زر PDF على اللافتة في آخر الحبل.</p>"""),
        ("كيف أغطّي المعلومات الخاصة؟",
         """<p>افتح الإعدادات › الخصوصية واختر ما يُغطّى. ولتغطية شيء فاتته التغطية، اضغط مطوّلًا على اللقطة واختر «إخفاء جزء…».</p>"""),
        ("على أي أجهزة Mac يعمل Snapfly؟",
         """<p>على macOS 14 Sonoma أو أحدث، بمعالجات Apple silicon و Intel. تحتاج «ترجمة النص» إلى macOS 15. ويكتب «وصف ذكي» بـ Apple Intelligence إن كانت في جهازك، وإلا فيستخدم عنوان اللقطة.</p>"""),
        ("كيف أحذف Snapfly؟",
         """<p>أغلقه من قائمته في شريط القوائم، ثم اسحب Snapfly من «التطبيقات» إلى سلة المهملات. واللقطات التي احتفظت بها تبقى حيث حفظتها.</p>"""),
        ("شيء آخر لا يعمل.",
         f"""<p>راسلنا على <a href="mailto:{EMAIL}"><bdi>{EMAIL}</bdi></a> واذكر إصدار macOS وما حدث. لقطة الشاشة تساعد. ويمكنك أيضًا <a href="{REPO}/issues">فتح بلاغ على GitHub</a>.</p>"""),
    ],

    notfound_title="الصفحة غير موجودة",
    notfound_p="هذه الصفحة ليست على الحبل.",
    notfound_link="إلى الصفحة الرئيسية",
)
