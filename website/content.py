# The words on the Snapfly website, in English, German and Arabic.
# Labels the app itself shows (menu items, settings, line styles) are not
# here: build.py reads them from the app's Localizable.strings, so the site
# always says what the app says.

import os

# Where the site lives. GitHub Pages is the default; a host with its own
# domain (Vercel) sets SNAPFLY_SITE_URL to that address, ending in a slash.
SITE_URL = os.environ.get("SNAPFLY_SITE_URL") or "https://mgrd281.github.io/Screenshots/"
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
    desc_privacy="Snapfly collects no data. It runs entirely on your Mac, and the only thing it asks the internet is the time.",
    title_support="Support · Snapfly",
    desc_support="Help with Snapfly, the screenshot line for the Mac, and how to reach us.",
    skip="Skip to content",
    nav_features="Features",
    nav_privacy="Privacy",
    nav_support="Support",
    lang_label="Language",
    brand_label="Color theme",
    brand_sunset="Original Sunset",
    brand_emerald="Emerald Petrol",
    brand_orange="Signature Orange",
    menu_label="Snapfly",

    hero_sub="Every screenshot you take hangs on a line at the top of your screen. Click one to copy it, or send it straight into the chat you’re typing in. Names and other private details are covered first, whether it goes to ChatGPT or to a person.",
    cta="Download for Mac",
    badge_for="Download for",
    cta_note="Free · macOS 14 or later · Apple silicon and Intel",
    try_hint="Try it: drag a screenshot along the line to change the order. Send one with its paper plane, or all of them with Snapfly’s button over the chat. Hold that button to add a message.",
    chat_title="Chat",
    chat_in="Can you send me yesterday’s invoice?",
    chat_reply="Got it, thanks!",
    chat_reply_all="Got them all, thanks!",
    send_all="Send all",
    send_all_label="Send all the screenshots to the chat",
    chat_placeholder="Message",
    chat_label="A chat window, the app in front",
    send_label="Send to chat",
    card_names=["Invoice", "Map", "Sales chart", "Calendar", "Sunset photo"],
    line_label="Screenshots hanging on Snapfly’s line",
    refill="New screenshots",

    send_h="All of them into WhatsApp or ChatGPT, with one click.",
    send_p="The send button at the end of the line pastes every screenshot on it into the app in front, WhatsApp, ChatGPT or any chat, right where you were typing. Each screenshot also carries its own paper plane, to send just that one. <span class='chord'><kbd>⌃</kbd><kbd>⌥</kbd><kbd>V</kbd></span> sends the newest one without reaching for the mouse. Once sent, it leaves the line, so the line only holds what’s still to send. Over WhatsApp, ChatGPT and other chats, a send button sits right above their own. Hold it to add a message, which arrives after the photos.",
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

    chatbtn_label="Send all the screenshots to the chat",
    chatbtn_hold="Hold to add a message",
    caption_reply="Perfect, thank you!",

    cap_h="One click, and it’s on the line.",
    cap_p="Press <span class='chord'><kbd>⌃</kbd><kbd>⌥</kbd><kbd>S</kbd></span> or click the screenshot button at the edge of the screen, then drag over an area, click a window or take the whole screen. It hangs on the line at once: no file on the Desktop, nothing to wait for. A menu that closes when you click? Take it with a timer. Something that moves? Record it.",
    desk=dict(
        label="A Mac desktop with Snapfly on it. Everything on it works.",
        note="Everything here works, with the pointer, by touch or with the keyboard.",
        guide="Start the guide",
        clock="Fri Oct 23  9:41 AM",
        desktop="Desktop", browser="Browser", chat="Messages", trash="Trash", dock="Dock",
        close="Close", minimize="Minimize",
        url="flights.example", route="Berlin → Lisbon", when="Fri, Oct 23 · 1 adult",
        sort="Sort", sort_items=["Price", "Duration", "Departure"],
        flights=[("07:10 – 10:50", "3 h 40 min · Nonstop", "€89", 89, 220, 430),
                 ("09:30 – 13:05", "3 h 35 min · Nonstop", "€112", 112, 215, 570),
                 ("06:20 – 11:55", "5 h 35 min · 1 stop", "€97", 97, 335, 380)],
        cheapest="Cheapest",
        person="Lena", chat_in=["Did you find flights?", "Send me a screenshot!"], chat_reply="Perfect, thanks!", field="Message",
        line="Screenshots on the line", shot="Screenshot {n}", rec="Recording {n}",
        trash_empty="The Trash is empty.", put_back="Put Back", empty_trash="Empty Trash",
        toast=dict(taken="Screenshot taken", recorded="Recording saved", copied="Copied", paste="Paste in Messages",
                   removed="Screenshot removed", cleared="Line cleared", sent="Sent to Lena", closed="{app} closed",
                   restored="Put back", emptied="Trash emptied", timer_off="Timer cancelled",
                   button_off="Screenshot button hidden", nothing="Nothing on the line yet. Take a screenshot first.",
                   undo="Undo", open="Open"),
        step_of="Step {n} of {total}", show="Show me", skip="Skip", close_guide="Close guide", again="Start over",
        steps=[("Take a screenshot", "Click the round button at the edge, or press ⌃⌥S."),
               ("Choose an area", "Drag over part of the flight search. Return takes the whole screen."),
               ("It’s on the line", "Click the picture to copy it."),
               ("Open Messages", "Open the chat from the Dock. Snapfly shows its send button there."),
               ("Send with one click", "The button above the chat sends everything on the line."),
               ("Timer and recording", "Snapfly’s menu at the top has a timer and screen recording.")],
        done=("You did it", "That’s how simple Snapfly is. Get it for your Mac."),
    ),

    start_h="Start in four steps.",
    start_p="From the download to your first screenshot on the line.",
    start=[
        ("Download it", "Download Snapfly.zip, open it, and drag Snapfly into your Applications folder. It’s signed and notarized by Apple."),
        ("Open it", "Snapfly lives in the menu bar as a little shirt, with no Dock icon. The first time, choose Turn on, and your screenshots hang on the line instead of the Desktop."),
        ("Allow it", "The first time you take or send a screenshot, macOS asks you to allow Screen Recording or Accessibility. Settings › Permissions shows each one, with one button to allow it."),
        ("Take your first one", "Press ⌃⌥S and drag over anything. Click it on the line to copy it, or click its paper plane to send it into the chat you’re typing in."),
    ],

    say_h="Say what to hide.",
    say_p="Hold a screenshot, choose Hide Part…, and say it in your own words, like “everything but the amount and the date”. With Apple Intelligence, Snapfly understands the whole sentence, on your Mac. Without it, type the words to hide. Or drag a box over anything.",
    say_try="Try it: click an example, or write your own.",
    say_file="Screenshot 2026-10-23 at 09.41.12",
    say_label="The Hide Part window, with a bank transfer in it",
    rcpt=dict(title="Transfer sent", date="October 23, 2026 · 09:41", amount="€1,250.00",
              from_l="From", to_l="To", ref_l="Reference", addr_l="Address", email_l="Email", phone_l="Phone",
              from_name="Lena Hoffmann", from_iban="DE89 3704 0044 0532 0130 00",
              to_name="Jonas Weber", to_iban="DE02 1203 0000 0000 2020 51",
              ref="Rent for November", addr="Lindenstraße 12, 10969 Berlin",
              email="lena.hoffmann@example.com", phone="+49 30 1234 5678"),

    styles_h="Four ways to hang.",
    styles_p="Pick what your screenshots hang on. Everything else works the same on each.",
    styles={
        "Clothesline": "Crooked photos swaying on clips.",
        "Glass shelf": "Upright on a shelf of Liquid Glass, like the Dock.",
        "Island": "Black, hanging from the top of the screen like the notch grown wide.",
        "Card stack": "A stack by the right edge that spreads out as you reach it, with a count on top.",
    },

    design_h="Nothing leaves your Mac.",
    design_points=["No account.", "No cloud.", "No analytics."],
    design_p="Reading text, covering details, translating and describing all happen on your Mac, with Apple’s own frameworks. Nothing you capture is uploaded anywhere.",
    design_link="Read the privacy policy",

    close_h="Hang your first screenshot.",
    close_note="Free · macOS 14 or later · Apple silicon and Intel · 13 languages · Signed and notarized by Apple",

    footer_made=f"Made by {MAKER}.",
    footer_based="Based on Tendedero by Alejandro Buján, under the MIT License.",
    footer_tm="Mac and macOS are trademarks of Apple Inc.",
    footer_source="Source code",
    footer_contact="Contact",

    updated_label="Last updated",
    updated="October 16, 2026",

    privacy_title="Privacy Policy",
    privacy_short_h="In short",
    privacy_short="Snapfly collects no personal data. It works entirely on your Mac; its only connection is to ask an atomic clock for the time, for the time stamp. This website sets no cookies and uses no analytics.",
    privacy=[
        ("Who is responsible",
         f"""<p>Snapfly is made by {MAKER}. For any question about privacy, write to <a href="mailto:{EMAIL}">{EMAIL}</a>.</p>"""),
        ("The Snapfly app",
         """<ul>
<li><strong>No data is collected.</strong> Snapfly has no account, no analytics, no advertising and no tracking. It does not send your screenshots, their text or anything about you to us or to anyone else.</li>
<li><strong>Nothing leaves your Mac.</strong> Reading the text in a screenshot, covering private details, searching, translating and describing all run on your Mac, with Apple’s frameworks.</li>
<li><strong>The time stamp.</strong> While Stamp the date and time is on, Snapfly asks the atomic clock of the PTB, Germany’s national metrology institute (ptbtime1.ptb.de), for the exact time of each new screenshot, the way a clock sets itself (NTP). Only that question goes out, with no data about you or your screenshots. With the stamp off, the app never connects to the internet.</li>
<li><strong>Your files.</strong> Snapfly reads the screenshots in the folders you let it watch, and in the Mac App Store edition the Snapfly folder in Pictures. It copies, sends, moves or deletes a screenshot only when you ask it to, or, if you leave that setting on, after you have sent it into a chat.</li>
<li><strong>Copied images.</strong> If you turn on Hang copied images, Snapfly looks at images you copy, to hang them on the line. It leaves alone anything copied together with text or a file, and anything a password manager marks as private.</li>
<li><strong>The Accessibility permission</strong> lets the send button paste a screenshot into the app you are using, by pressing ⌘V there. Snapfly uses it for nothing else. You can turn it off at any time in System Settings › Privacy &amp; Security › Accessibility.</li>
<li><strong>The Screen Recording permission</strong> lets Snapfly take the screenshots and recordings you ask for, with ⌃⌥S, the screenshot button or Record Screen. It captures only when you ask, and what it takes stays on your Mac.</li>
<li><strong>Browsers.</strong> So that the send button shows only on chat websites, Snapfly asks the browser in front for the address of the page that is open, once you allow it. While the time stamp is on, it also writes that address on the stamp of a new screenshot, which stays on your Mac with it. It reads nothing else from the browser.</li>
<li>Settings › Permissions shows each of these, whether it is allowed, and how to change it.</li>
<li><strong>Your settings</strong>, such as the line style and what to cover, are stored on your Mac only.</li>
</ul>"""),
        ("Apple’s services",
         """<p>Translate Text uses Apple’s translation on your Mac; macOS may download language files from Apple for it. Describe, and Hide Part when you say what to hide in a sentence, use Apple Intelligence on your Mac. When you get Snapfly from the Mac App Store or TestFlight, Apple handles that under its own privacy policy. If you have agreed to share analytics with app developers, Apple may give us anonymous crash reports and usage statistics, which we use only to fix problems. See <a href="https://www.apple.com/legal/privacy/">Apple’s privacy policy</a>.</p>"""),
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
        ("How do I take a screenshot with Snapfly?",
         """<p>Press <span class='chord'><kbd>⌃</kbd><kbd>⌥</kbd><kbd>S</kbd></span>, or click the screenshot button at the edge of the screen. Then drag over an area, click a window, or press Return for the whole screen. It hangs on the line at once. The first time, macOS asks you to allow Screen Recording for Snapfly.</p>
<p>For a menu that closes when you click, choose Take Screenshot with Timer in Snapfly’s menu in the menu bar and pick the seconds, then open the menu before the countdown ends.</p>"""),
        ("How do I record the screen?",
         """<p>Choose Record Screen in Snapfly’s menu in the menu bar, or press <span class='chord'><kbd>⌃</kbd><kbd>⌥</kbd><kbd>R</kbd></span>. Drag over an area or click a window. To stop, click the red button at the bottom of the screen. The recording hangs on the line; hold it and choose Make GIF to turn it into a GIF.</p>"""),
        ("How do I send a message with the photos?",
         """<p>Press and hold the send button over the chat, or right-click it and choose Send with a Message…. Write your message and press Return: the photos go first, then your words.</p>"""),
        ("How do I change the order on the line?",
         """<p>Drag a screenshot left or right along the line. Send all and Copy all keep that order. With VoiceOver, use Move Earlier and Move Later.</p>"""),
        ("How do I send a screenshot into a chat?",
         """<p>Click into the chat’s message field, then click the paper plane on a screenshot. Or press <span class='chord'><kbd>⌃</kbd><kbd>⌥</kbd><kbd>V</kbd></span> to send the newest one. To send several at once, ⌘-click them first.</p>"""),
        ("The send button says “Not allowed yet”.",
         """<p>Sending presses ⌘V for you, and macOS asks for the Accessibility permission for that. Settings › Permissions in Snapfly shows each permission it uses, whether it is allowed, and one button to allow it.</p>
<ol>
<li>Open System Settings › Privacy &amp; Security › Accessibility.</li>
<li>If Snapfly is in the list, switch it on.</li>
<li>If it isn’t, click +, choose Snapfly in Applications, click Open and switch it on.</li>
<li>Quit Snapfly and open it again.</li>
</ol>"""),
        ("How do I make a PDF?",
         """<p>Press and hold a screenshot, or right-click it, and choose Make PDF. To put several screenshots in one PDF, ⌘-click them first, then click the PDF button on the tag at the end of the line.</p>"""),
        ("How do I cover private details?",
         """<p>Open Settings › Privacy and check what to cover. To cover anything it missed, hold the screenshot and choose Hide Part…, then drag over it or say what to hide, like “everything but the amount and the date”.</p>"""),
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
    desc_privacy="Snapfly erhebt keine Daten. Die App läuft vollständig auf deinem Mac, und das Internet fragt sie nur nach der Uhrzeit.",
    title_support="Support · Snapfly",
    desc_support="Hilfe zu Snapfly, der Leine für Bildschirmfotos auf dem Mac, und wie du uns erreichst.",
    skip="Zum Inhalt springen",
    nav_features="Funktionen",
    nav_privacy="Datenschutz",
    nav_support="Support",
    lang_label="Sprache",
    brand_label="Farbthema",
    brand_sunset="Original Sunset",
    brand_emerald="Emerald Petrol",
    brand_orange="Signature Orange",
    menu_label="Snapfly",

    hero_sub="Jedes Bildschirmfoto hängt an einer Leine oben auf deinem Bildschirm. Ein Klick kopiert es, oder du schickst es direkt in den Chat, in dem du gerade schreibst. Namen und andere private Angaben werden vorher verdeckt, ob es an ChatGPT geht oder an einen Menschen.",
    cta="Für Mac laden",
    badge_for="Laden für",
    cta_note="Kostenlos · ab macOS 14 · Apple Silicon und Intel",
    try_hint="Probier’s aus: Zieh ein Bild an der Leine entlang, um die Reihenfolge zu ändern. Schick eines mit seinem Papierflieger oder alle mit der Taste von Snapfly über dem Chat. Halt diese Taste gedrückt, um eine Nachricht dazuzuschreiben.",
    chat_title="Chat",
    chat_in="Kannst du mir die Rechnung von gestern schicken?",
    chat_reply="Ist angekommen, danke!",
    chat_reply_all="Alle angekommen, danke!",
    send_all="Alle senden",
    send_all_label="Alle Bildschirmfotos in den Chat senden",
    chat_placeholder="Nachricht",
    chat_label="Ein Chatfenster, die App im Vordergrund",
    send_label="In den Chat senden",
    card_names=["Rechnung", "Karte", "Umsatzdiagramm", "Kalender", "Foto vom Sonnenuntergang"],
    line_label="Bildschirmfotos an der Leine von Snapfly",
    refill="Neue Bildschirmfotos",

    send_h="Alle auf einmal in WhatsApp oder ChatGPT, mit einem Klick.",
    send_p="Die Senden-Taste am Ende der Leine setzt alle Bildschirmfotos darauf in die App im Vordergrund ein – WhatsApp, ChatGPT oder jeden Chat –, genau dort, wo du gerade schreibst. Jedes Bildschirmfoto hat außerdem einen eigenen Papierflieger, um nur dieses zu senden. <span class='chord'><kbd>⌃</kbd><kbd>⌥</kbd><kbd>V</kbd></span> schickt das neueste, ohne dass du zur Maus greifst. Was gesendet ist, verlässt die Leine. So hängt dort nur, was noch zu senden ist. Über WhatsApp, ChatGPT und anderen Chats sitzt eine Senden-Taste direkt über ihrer eigenen. Halt sie gedrückt, um eine Nachricht dazuzuschreiben: Sie kommt nach den Bildern an.",
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

    chatbtn_label="Alle Bildschirmfotos in den Chat senden",
    chatbtn_hold="Gedrückt halten für eine Nachricht",
    caption_reply="Perfekt, danke dir!",

    cap_h="Ein Klick, und es hängt an der Leine.",
    cap_p="Drück <span class='chord'><kbd>⌃</kbd><kbd>⌥</kbd><kbd>S</kbd></span> oder klick auf die Bildschirmfoto-Taste am Bildschirmrand, dann zieh über einen Bereich, klick auf ein Fenster oder nimm den ganzen Bildschirm. Es hängt sofort an der Leine: keine Datei auf dem Schreibtisch, kein Warten. Ein Menü, das beim Klicken zugeht? Nimm es mit Timer auf. Etwas bewegt sich? Nimm den Bildschirm auf.",
    desk=dict(
        label="Ein Mac-Schreibtisch mit Snapfly. Alles darauf funktioniert.",
        note="Alles hier funktioniert – mit Zeiger, Touch oder Tastatur.",
        guide="Anleitung starten",
        clock="Fr. 23. Okt.  09:41",
        desktop="Schreibtisch", browser="Browser", chat="Nachrichten", trash="Papierkorb", dock="Dock",
        close="Schließen", minimize="Minimieren",
        url="flights.example", route="Berlin → Lissabon", when="Fr., 23. Okt. · 1 Erwachsener",
        sort="Sortieren", sort_items=["Preis", "Dauer", "Abflug"],
        flights=[("07:10 – 10:50", "3 Std. 40 Min. · Direkt", "89 €", 89, 220, 430),
                 ("09:30 – 13:05", "3 Std. 35 Min. · Direkt", "112 €", 112, 215, 570),
                 ("06:20 – 11:55", "5 Std. 35 Min. · 1 Stopp", "97 €", 97, 335, 380)],
        cheapest="Am günstigsten",
        person="Lena", chat_in=["Hast du schon Flüge gefunden?", "Schick mir einen Screenshot!"], chat_reply="Perfekt, danke!", field="Nachricht",
        line="Bildschirmfotos an der Leine", shot="Bildschirmfoto {n}", rec="Aufnahme {n}",
        trash_empty="Der Papierkorb ist leer.", put_back="Zurücklegen", empty_trash="Papierkorb leeren",
        toast=dict(taken="Bildschirmfoto aufgenommen", recorded="Aufnahme gespeichert", copied="Kopiert", paste="In Nachrichten einfügen",
                   removed="Bildschirmfoto entfernt", cleared="Leine geleert", sent="An Lena gesendet", closed="{app} geschlossen",
                   restored="Zurückgelegt", emptied="Papierkorb geleert", timer_off="Timer abgebrochen",
                   button_off="Bildschirmfoto-Taste ausgeblendet", nothing="Noch nichts an der Leine. Mach zuerst ein Bildschirmfoto.",
                   undo="Rückgängig", open="Öffnen"),
        step_of="Schritt {n} von {total}", show="Zeig es mir", skip="Überspringen", close_guide="Anleitung schließen", again="Noch einmal",
        steps=[("Bildschirmfoto aufnehmen", "Klick auf die runde Taste am Rand oder drück ⌃⌥S."),
               ("Bereich auswählen", "Zieh über einen Teil der Flugsuche. Return nimmt den ganzen Bildschirm."),
               ("Es hängt an der Leine", "Klick auf das Bild, um es zu kopieren."),
               ("Nachrichten öffnen", "Öffne den Chat im Dock. Snapfly zeigt dort seine Senden-Taste."),
               ("Mit einem Klick senden", "Die Taste über dem Chat schickt alles von der Leine."),
               ("Timer und Aufnahme", "Im Snapfly-Menü oben findest du Timer und Bildschirmaufnahme.")],
        done=("Geschafft", "So einfach ist Snapfly. Hol es dir für deinen Mac."),
    ),

    start_h="In vier Schritten startklar.",
    start_p="Vom Download bis zu deinem ersten Bildschirmfoto an der Leine.",
    start=[
        ("Laden", "Lade Snapfly.zip, öffne die Datei und zieh Snapfly in deinen Ordner „Programme“. Snapfly ist von Apple signiert und beglaubigt."),
        ("Öffnen", "Snapfly lebt in der Menüleiste, als kleines T-Shirt, ohne Symbol im Dock. Wähl beim ersten Mal „Einschalten“, dann hängen deine Bildschirmfotos an der Leine statt auf dem Schreibtisch."),
        ("Erlauben", "Wenn du zum ersten Mal ein Bildschirmfoto machst oder sendest, bittet macOS um die Bildschirmaufnahme oder die Bedienungshilfen. Einstellungen › Berechtigungen zeigt jede davon, mit einer Taste zum Erlauben."),
        ("Das erste Bild", "Drück ⌃⌥S und zieh über irgendetwas. Klick es an der Leine an, um es zu kopieren, oder auf seinen Papierflieger, um es in den Chat zu schicken, in dem du gerade schreibst."),
    ],

    say_h="Sag, was verdeckt wird.",
    say_p="Halt ein Bildschirmfoto gedrückt, wähl „Bereich verdecken …“ und sag es mit deinen Worten, etwa „alles außer Betrag und Datum“. Mit Apple Intelligence versteht Snapfly den ganzen Satz, auf deinem Mac. Ohne tippst du die Wörter, die weg sollen. Oder zieh ein Rechteck über irgendetwas.",
    say_try="Probier’s aus: Klick auf ein Beispiel oder schreib selbst etwas.",
    say_file="Bildschirmfoto 2026-10-23 um 09.41.12",
    say_label="Das Fenster „Bereich verdecken“ mit einer Überweisung darin",
    rcpt=dict(title="Überweisung ausgeführt", date="23. Oktober 2026 · 09:41", amount="1.250,00 €",
              from_l="Von", to_l="An", ref_l="Verwendungszweck", addr_l="Adresse", email_l="E-Mail", phone_l="Telefon",
              from_name="Lena Hoffmann", from_iban="DE89 3704 0044 0532 0130 00",
              to_name="Jonas Weber", to_iban="DE02 1203 0000 0000 2020 51",
              ref="Miete November", addr="Lindenstraße 12, 10969 Berlin",
              email="lena.hoffmann@example.com", phone="+49 30 1234 5678"),

    styles_h="Vier Arten zu hängen.",
    styles_p="Wähle, woran deine Bildschirmfotos hängen. Alles andere funktioniert überall gleich.",
    styles={
        "Clothesline": "Schiefe Bilder, die an Klammern schaukeln.",
        "Glass shelf": "Aufrecht auf einem Regal aus Liquid Glass, wie das Dock.",
        "Island": "Schwarz, von oben herab, wie eine breit gewordene Notch.",
        "Card stack": "Ein Stapel am rechten Rand, der sich auffächert, wenn du hingehst, mit der Anzahl obendrauf.",
    },

    design_h="Nichts verlässt deinen Mac.",
    design_points=["Kein Konto.", "Keine Cloud.", "Keine Analyse."],
    design_p="Text lesen, Angaben verdecken, übersetzen und beschreiben: Das alles passiert auf deinem Mac, mit Apples eigenen Frameworks. Nichts, was du aufnimmst, wird irgendwohin hochgeladen.",
    design_link="Datenschutzerklärung lesen",

    close_h="Häng dein erstes Bildschirmfoto auf.",
    close_note="Kostenlos · ab macOS 14 · Apple Silicon und Intel · 13 Sprachen · Von Apple signiert und beglaubigt",

    footer_made=f"Gemacht von {MAKER}.",
    footer_based="Basiert auf Tendedero von Alejandro Buján, unter der MIT-Lizenz.",
    footer_tm="Mac und macOS sind Marken der Apple Inc.",
    footer_source="Quellcode",
    footer_contact="Kontakt",

    updated_label="Stand",
    updated="16. Oktober 2026",

    privacy_title="Datenschutzerklärung",
    privacy_short_h="Kurz gesagt",
    privacy_short="Snapfly erhebt keine personenbezogenen Daten. Die App arbeitet vollständig auf deinem Mac; ihre einzige Verbindung fragt für den Zeitstempel eine Atomuhr nach der Uhrzeit. Diese Website setzt keine Cookies und nutzt keine Analyse.",
    privacy=[
        ("Verantwortlich",
         f"""<p>Snapfly wird von {MAKER} entwickelt. Bei Fragen zum Datenschutz schreib an <a href="mailto:{EMAIL}">{EMAIL}</a>.</p>"""),
        ("Die App Snapfly",
         """<ul>
<li><strong>Es werden keine Daten erhoben.</strong> Snapfly hat kein Konto, keine Analyse, keine Werbung und kein Tracking. Die App sendet weder deine Bildschirmfotos noch deren Text noch irgendetwas über dich an uns oder an Dritte.</li>
<li><strong>Nichts verlässt deinen Mac.</strong> Texterkennung, das Verdecken privater Angaben, die Suche, das Übersetzen und Beschreiben laufen auf deinem Mac, mit Apples Frameworks.</li>
<li><strong>Der Zeitstempel.</strong> Solange „Datum und Uhrzeit stempeln“ eingeschaltet ist, fragt Snapfly für jedes neue Bildschirmfoto die Atomuhr der PTB, der Physikalisch-Technischen Bundesanstalt (ptbtime1.ptb.de), nach der genauen Uhrzeit – so, wie sich eine Uhr stellt (NTP). Nur diese Frage geht hinaus, ohne Daten über dich oder deine Bildschirmfotos. Ist der Stempel aus, verbindet sich die App nie mit dem Internet.</li>
<li><strong>Deine Dateien.</strong> Snapfly liest die Bildschirmfotos in den Ordnern, die du freigibst, in der Mac App Store-Ausgabe außerdem den Ordner „Snapfly“ in „Bilder“. Die App kopiert, sendet, verschiebt oder löscht ein Bildschirmfoto nur, wenn du es willst, oder – wenn du die Einstellung eingeschaltet lässt – nachdem du es in einen Chat gesendet hast.</li>
<li><strong>Kopierte Bilder.</strong> Wenn du „Kopierte Bilder aufhängen“ einschaltest, sieht sich Snapfly Bilder an, die du kopierst, um sie an die Leine zu hängen. Was zusammen mit Text oder einer Datei kopiert wurde und was ein Passwortmanager als privat markiert, bleibt unberührt.</li>
<li><strong>Die Berechtigung für Bedienungshilfen</strong> erlaubt der Senden-Taste, ein Bildschirmfoto in die App einzusetzen, die du gerade benutzt, indem sie dort ⌘V drückt. Snapfly nutzt sie für nichts anderes. Du kannst sie jederzeit unter Systemeinstellungen › Datenschutz &amp; Sicherheit › Bedienungshilfen ausschalten.</li>
<li><strong>Die Berechtigung für Bildschirmaufnahme</strong> erlaubt Snapfly, die Bildschirmfotos und Aufnahmen zu machen, um die du bittest – mit ⌃⌥S, der Bildschirmfoto-Taste oder „Bildschirm aufnehmen“. Snapfly nimmt nur auf, wenn du es willst, und was es aufnimmt, bleibt auf deinem Mac.</li>
<li><strong>Browser.</strong> Damit die Senden-Taste nur auf Chat-Websites erscheint, fragt Snapfly den Browser im Vordergrund nach der Adresse der geöffneten Seite, sobald du es erlaubst. Ist der Zeitstempel eingeschaltet, schreibt es diese Adresse auch auf den Stempel eines neuen Bildschirmfotos, der mit ihm auf deinem Mac bleibt. Sonst liest es nichts aus dem Browser.</li>
<li>Einstellungen › Berechtigungen zeigt jede davon, ob sie erlaubt ist und wie du das änderst.</li>
<li><strong>Deine Einstellungen</strong>, etwa der Stil der Leine und was verdeckt wird, werden nur auf deinem Mac gespeichert.</li>
</ul>"""),
        ("Dienste von Apple",
         """<p>„Text übersetzen“ nutzt Apples Übersetzung auf deinem Mac; macOS lädt dafür eventuell Sprachdateien von Apple. „Beschreiben“ und „Bereich verdecken“, wenn du in einem Satz sagst, was verdeckt wird, nutzen Apple Intelligence auf deinem Mac. Wenn du Snapfly aus dem Mac App Store oder über TestFlight lädst, verarbeitet Apple das nach seiner eigenen Datenschutzrichtlinie. Wenn du zugestimmt hast, Analysedaten mit App-Entwicklern zu teilen, kann Apple uns anonyme Absturzberichte und Nutzungsstatistiken geben, die wir nur zur Fehlerbehebung verwenden. Siehe die <a href="https://www.apple.com/de/legal/privacy/">Datenschutzrichtlinie von Apple</a>.</p>"""),
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
        ("Wie mache ich ein Bildschirmfoto mit Snapfly?",
         """<p>Drück <span class='chord'><kbd>⌃</kbd><kbd>⌥</kbd><kbd>S</kbd></span> oder klick auf die Bildschirmfoto-Taste am Bildschirmrand. Dann zieh über einen Bereich, klick auf ein Fenster oder drück Return für den ganzen Bildschirm. Es hängt sofort an der Leine. Beim ersten Mal bittet macOS dich, Snapfly die Bildschirmaufnahme zu erlauben.</p>
<p>Für ein Menü, das beim Klicken zugeht, wähl im Menü von Snapfly in der Menüleiste „Bildschirmfoto mit Timer“ und die Sekunden. Öffne dann das Menü, bevor der Countdown endet.</p>"""),
        ("Wie nehme ich den Bildschirm auf?",
         """<p>Wähl „Bildschirm aufnehmen“ im Menü von Snapfly in der Menüleiste oder drück <span class='chord'><kbd>⌃</kbd><kbd>⌥</kbd><kbd>R</kbd></span>. Zieh über einen Bereich oder klick auf ein Fenster. Zum Beenden klickst du auf die rote Taste unten auf dem Bildschirm. Die Aufnahme hängt an der Leine; halt sie gedrückt und wähl „GIF erstellen“, um ein GIF daraus zu machen.</p>"""),
        ("Kann ich eine Nachricht mit den Bildern senden?",
         """<p>Halt die Senden-Taste über dem Chat gedrückt oder klick mit rechts darauf und wähl „Mit Nachricht senden …“. Schreib deine Nachricht und drück Return: Erst kommen die Bilder, dann deine Worte.</p>"""),
        ("Wie ändere ich die Reihenfolge an der Leine?",
         """<p>Zieh ein Bildschirmfoto an der Leine nach links oder rechts. „Alle senden“ und „Alle kopieren“ behalten diese Reihenfolge. Mit VoiceOver nutzt du „Nach vorne“ und „Nach hinten“.</p>"""),
        ("Wie sende ich ein Bildschirmfoto in einen Chat?",
         """<p>Klick in das Nachrichtenfeld des Chats und dann auf den Papierflieger eines Bildschirmfotos. Oder drück <span class='chord'><kbd>⌃</kbd><kbd>⌥</kbd><kbd>V</kbd></span>, um das neueste zu senden. Um mehrere auf einmal zu senden, klick sie vorher mit ⌘ an.</p>"""),
        ("Die Senden-Taste zeigt „Noch nicht erlaubt“.",
         """<p>Beim Senden drückt Snapfly für dich ⌘V, und dafür fragt macOS nach der Berechtigung für Bedienungshilfen. Einstellungen › Berechtigungen in Snapfly zeigt jede Berechtigung, die es nutzt, ob sie erlaubt ist, und eine Taste, um sie zu erlauben.</p>
<ol>
<li>Öffne Systemeinstellungen › Datenschutz &amp; Sicherheit › Bedienungshilfen.</li>
<li>Steht Snapfly in der Liste, schalte es ein.</li>
<li>Wenn nicht, klick auf +, wähl Snapfly in „Programme“, klick auf „Öffnen“ und schalte es ein.</li>
<li>Beende Snapfly und öffne es wieder.</li>
</ol>"""),
        ("Wie erstelle ich ein PDF?",
         """<p>Halt ein Bildschirmfoto gedrückt oder klick mit rechts darauf und wähl „PDF erstellen“. Für mehrere Bildschirmfotos in einem PDF klickst du sie vorher mit ⌘ an und dann auf die PDF-Taste am Schild am Ende der Leine.</p>"""),
        ("Wie verdecke ich private Angaben?",
         """<p>Öffne Einstellungen › Datenschutz und wähle, was verdeckt werden soll. Um etwas zu verdecken, das übersehen wurde, halt das Bildschirmfoto gedrückt und wähl „Bereich verdecken …“. Dann zieh darüber oder sag, was verdeckt wird, etwa „alles außer Betrag und Datum“.</p>"""),
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
    desc_privacy="لا يجمع Snapfly أي بيانات. يعمل بالكامل على جهاز Mac، ولا يسأل الإنترنت إلا عن الوقت.",
    title_support="الدعم · Snapfly",
    desc_support="مساعدة في استخدام Snapfly، حبل لقطات الشاشة على Mac، وطريقة التواصل معنا.",
    skip="انتقل إلى المحتوى",
    nav_features="المزايا",
    nav_privacy="الخصوصية",
    nav_support="الدعم",
    lang_label="اللغة",
    brand_label="سمة الألوان",
    brand_sunset="الغروب الأصلي",
    brand_emerald="الزمرّد البترولي",
    brand_orange="البرتقالي المميّز",
    menu_label="Snapfly",

    hero_sub="كل لقطة شاشة تلتقطها تُعلَّق على حبل في أعلى شاشتك. انقرها لتنسخها، أو أرسلها مباشرة إلى الدردشة التي تكتب فيها. والأسماء وغيرها من المعلومات الخاصة تُغطّى قبل الإرسال، سواء ذهبت إلى ChatGPT أو إلى شخص.",
    cta="تنزيل لجهاز Mac",
    badge_for="حمّله لنظام",
    cta_note="مجاني · macOS 14 أو أحدث · Apple silicon و Intel",
    try_hint="جرّبه: اسحب لقطة على طول الحبل لتغيّر ترتيبها. أرسل واحدة بطائرتها الورقية، أو كلها بزر Snapfly فوق الدردشة. واضغط على هذا الزر مطوّلًا لتضيف رسالة.",
    chat_title="دردشة",
    chat_in="ممكن ترسل لي فاتورة أمس؟",
    chat_reply="وصلت، شكرًا!",
    chat_reply_all="وصلت كلها، شكرًا!",
    send_all="إرسال الكل",
    send_all_label="إرسال كل اللقطات إلى الدردشة",
    chat_placeholder="رسالة",
    chat_label="نافذة دردشة، التطبيق الذي أمامك",
    send_label="إرسال إلى الدردشة",
    card_names=["فاتورة", "خريطة", "رسم بياني للمبيعات", "تقويم", "صورة غروب"],
    line_label="لقطات شاشة معلّقة على حبل Snapfly",
    refill="لقطات جديدة",

    send_h="كلها إلى WhatsApp أو ChatGPT، بنقرة واحدة.",
    send_p="زر الإرسال في آخر الحبل يلصق كل اللقطات المعلّقة عليه في التطبيق الذي أمامك، WhatsApp أو ChatGPT أو أي دردشة، في المكان الذي تكتب فيه. وعلى كل لقطة أيضًا طائرة ورقية لإرسالها وحدها. واختصار <bdi class=\"chord\" dir=\"ltr\"><kbd>⌃</kbd><kbd>⌥</kbd><kbd>V</kbd></bdi> يرسل أحدث لقطة دون أن تلمس الفأرة. وما يُرسَل يغادر الحبل، فلا يبقى عليه إلا ما لم يُرسَل بعد. وفوق WhatsApp و ChatGPT وغيرهما من الدردشات، يظهر زر إرسال فوق زرّها مباشرة. اضغط عليه مطوّلًا لتضيف رسالة تصل بعد الصور.",
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

    chatbtn_label="إرسال كل اللقطات إلى الدردشة",
    chatbtn_hold="اضغط مطوّلًا لتضيف رسالة",
    caption_reply="ممتاز، شكرًا لك!",

    cap_h="نقرة واحدة، وتصبح على الحبل.",
    cap_p="اضغط <bdi class=\"chord\" dir=\"ltr\"><kbd>⌃</kbd><kbd>⌥</kbd><kbd>S</kbd></bdi> أو انقر زر التصوير عند حافة الشاشة، ثم اسحب فوق منطقة، أو انقر نافذة، أو التقط الشاشة كلها. تُعلَّق اللقطة على الحبل فورًا: لا ملف على سطح المكتب ولا انتظار. قائمة تُغلق حين تنقر؟ التقطها بالمؤقت. شيء يتحرّك؟ سجّل الشاشة.",
    desk=dict(
        label="سطح مكتب Mac عليه Snapfly. كل ما فيه يعمل.",
        note="كل شيء هنا يعمل: بالمؤشر أو باللمس أو بلوحة المفاتيح.",
        guide="ابدأ الإرشاد",
        clock="الجمعة 23 أكتوبر  9:41 ص",
        desktop="سطح المكتب", browser="المتصفح", chat="الرسائل", trash="سلة المهملات", dock="Dock",
        close="إغلاق", minimize="تصغير",
        url="flights.example", route="برلين ← لشبونة", when="الجمعة 23 أكتوبر · بالغ واحد",
        sort="الترتيب", sort_items=["السعر", "المدة", "الإقلاع"],
        flights=[("07:10 – 10:50", "3 س 40 د · مباشرة", "89 €", 89, 220, 430),
                 ("09:30 – 13:05", "3 س 35 د · مباشرة", "112 €", 112, 215, 570),
                 ("06:20 – 11:55", "5 س 35 د · توقف واحد", "97 €", 97, 335, 380)],
        cheapest="الأرخص",
        person="لينا", chat_in=["هل وجدت رحلات؟", "أرسل لي لقطة شاشة!"], chat_reply="ممتاز، شكرًا!", field="رسالة",
        line="لقطات على الحبل", shot="لقطة {n}", rec="تسجيل {n}",
        trash_empty="سلة المهملات فارغة.", put_back="إرجاع", empty_trash="إفراغ السلة",
        toast=dict(taken="التُقطت اللقطة", recorded="حُفظ التسجيل", copied="نُسخت", paste="الصق في الرسائل",
                   removed="أُزيلت اللقطة", cleared="أُفرغ الحبل", sent="أُرسلت إلى لينا", closed="أُغلق {app}",
                   restored="أُرجعت", emptied="أُفرغت السلة", timer_off="أُلغي المؤقت",
                   button_off="أُخفي زر التصوير", nothing="لا شيء على الحبل بعد. التقط لقطة أولًا.",
                   undo="تراجع", open="فتح"),
        step_of="الخطوة {n} من {total}", show="أرني", skip="تخطّي", close_guide="إغلاق الإرشاد", again="من جديد",
        steps=[("التقط لقطة", "انقر الزر الدائري عند الحافة، أو اضغط \u2066⌃⌥S\u2069."),
               ("اختر منطقة", "اسحب فوق جزء من صفحة الرحلات. و Return يلتقط الشاشة كلها."),
               ("صارت على الحبل", "انقر الصورة لتنسخها."),
               ("افتح الرسائل", "افتح الدردشة من Dock. هناك يُظهر Snapfly زر الإرسال."),
               ("أرسل بنقرة", "الزر فوق الدردشة يرسل كل ما على الحبل."),
               ("المؤقت والتسجيل", "في قائمة Snapfly في الأعلى تجد المؤقت وتسجيل الشاشة.")],
        done=("أحسنت", "هذا هو Snapfly ببساطة. نزّله لجهاز Mac الخاص بك."),
    ),

    start_h="ابدأ في أربع خطوات.",
    start_p="من التنزيل حتى أول لقطة على الحبل.",
    start=[
        ("نزّله", "نزّل الملف Snapfly.zip وافتحه، ثم اسحب Snapfly إلى مجلد «التطبيقات». التطبيق موقّع ومُعتمَد من Apple."),
        ("افتحه", "يعيش Snapfly في شريط القوائم على شكل قميص صغير، وليس له أيقونة في Dock. في المرة الأولى اختر «تشغيل»، فتُعلَّق لقطاتك على الحبل بدل سطح المكتب."),
        ("اسمح له", "أول مرة تلتقط فيها لقطة أو ترسلها، يطلب منك macOS السماح بتسجيل الشاشة أو بتسهيلات الاستخدام. وتعرض الإعدادات › الأذونات كل إذن منها، مع زر واحد للسماح به."),
        ("أول لقطة", "اضغط \u2066⌃⌥S\u2069 واسحب فوق أي شيء. انقرها على الحبل لتنسخها، أو انقر طائرتها الورقية لترسلها إلى الدردشة التي تكتب فيها."),
    ],

    say_h="قل ما تريد إخفاءه.",
    say_p="اضغط مطوّلًا على لقطة، واختر «إخفاء جزء…»، ثم قلها بكلماتك، مثل «كل شيء ما عدا المبلغ والتاريخ». مع Apple Intelligence يفهم Snapfly الجملة كلها، على جهازك. ومن دونها اكتب الكلمات التي تريد إخفاءها. أو اسحب مربعًا فوق أي شيء.",
    say_try="جرّبه: انقر مثالًا، أو اكتب ما تريد.",
    say_file="لقطة شاشة 2026-10-23 في 9.41.12 ص",
    say_label="نافذة «إخفاء جزء» وفيها تحويل بنكي",
    rcpt=dict(title="تم التحويل", date="23 أكتوبر 2026 · 09:41", amount="1.250,00 €",
              from_l="من", to_l="إلى", ref_l="البيان", addr_l="العنوان", email_l="البريد", phone_l="الهاتف",
              from_name="لينا هوفمان", from_iban="DE89 3704 0044 0532 0130 00",
              to_name="يوناس فيبر", to_iban="DE02 1203 0000 0000 2020 51",
              ref="إيجار نوفمبر", addr="شارع ليندن 12، 10969 برلين",
              email="lena.hoffmann@example.com", phone="+49 30 1234 5678"),

    styles_h="أربع طرق للتعليق.",
    styles_p="اختر ما تُعلَّق عليه لقطاتك. وكل شيء آخر يعمل بالطريقة نفسها.",
    styles={
        "Clothesline": "صور مائلة تتأرجح على المشابك.",
        "Glass shelf": "صور منتصبة على رف من Liquid Glass، مثل Dock.",
        "Island": "سوداء، تتدلّى من أعلى الشاشة كأن النوتش اتّسعت.",
        "Card stack": "كومة عند حافة الشاشة تنفرد حين تقترب منها، وفوقها العدد.",
    },

    design_h="لا شيء يغادر جهازك.",
    design_points=["بلا حساب.", "بلا سحابة.", "بلا تتبّع."],
    design_p="قراءة النص وتغطية المعلومات والترجمة والوصف، كلها تحدث على جهاز Mac الخاص بك، بأدوات Apple نفسها. لا يُرفع شيء مما تلتقطه إلى أي مكان.",
    design_link="اقرأ سياسة الخصوصية",

    close_h="علّق أول لقطة شاشة لك.",
    close_note="مجاني · macOS 14 أو أحدث · Apple silicon و Intel · 13 لغة · موقّع ومُعتمَد من Apple",

    footer_made=f"من صنع {MAKER}.",
    footer_based="مبني على Tendedero من Alejandro Buján، بترخيص MIT.",
    footer_tm="Mac و macOS علامتان تجاريتان لشركة Apple Inc.",
    footer_source="الشيفرة المصدرية",
    footer_contact="تواصل معنا",

    updated_label="آخر تحديث",
    updated="16 أكتوبر 2026",

    privacy_title="سياسة الخصوصية",
    privacy_short_h="باختصار",
    privacy_short="لا يجمع Snapfly أي بيانات شخصية. يعمل بالكامل على جهاز Mac، واتصاله الوحيد سؤال ساعة ذرية عن الوقت من أجل ختم الوقت. وهذا الموقع لا يستخدم ملفات تعريف الارتباط (الكوكيز) ولا أدوات تحليل.",
    privacy=[
        ("المسؤول",
         f"""<p>يطوّر Snapfly <bdi>{MAKER}</bdi>. لأي سؤال عن الخصوصية، راسلنا على <a href="mailto:{EMAIL}"><bdi>{EMAIL}</bdi></a>.</p>"""),
        ("تطبيق Snapfly",
         """<ul>
<li><strong>لا تُجمع أي بيانات.</strong> لا حساب في Snapfly، ولا تحليلات، ولا إعلانات، ولا تتبّع. لا يرسل التطبيق لقطاتك ولا نصوصها ولا أي شيء عنك إلينا أو إلى أي أحد.</li>
<li><strong>لا يخرج شيء من جهازك.</strong> قراءة النص في اللقطة، وتغطية المعلومات الخاصة، والبحث، والترجمة، والوصف، كلها تعمل على جهازك بأدوات Apple.</li>
<li><strong>ختم الوقت.</strong> ما دام «اختم التاريخ والوقت» مفعّلًا، يسأل Snapfly الساعة الذرية لمعهد PTB الألماني للقياس (<bdi>ptbtime1.ptb.de</bdi>) عن الوقت الدقيق لكل لقطة جديدة، بالطريقة التي تضبط بها الساعات نفسها (NTP). لا يخرج إلا هذا السؤال، بلا أي بيانات عنك أو عن لقطاتك. وحين يكون الختم مطفأً، لا يتصل التطبيق بالإنترنت أبدًا.</li>
<li><strong>ملفاتك.</strong> يقرأ Snapfly لقطات الشاشة في المجلدات التي تسمح له بمراقبتها، وفي نسخة Mac App Store مجلد Snapfly داخل «الصور». ولا ينسخ لقطة أو يرسلها أو ينقلها أو يحذفها إلا حين تطلب ذلك، أو، إن أبقيت هذا الإعداد مفعّلًا، بعد أن ترسلها إلى دردشة.</li>
<li><strong>الصور المنسوخة.</strong> إن فعّلت «تعليق الصور المنسوخة»، ينظر Snapfly إلى الصور التي تنسخها ليعلّقها على الحبل. ويترك كل ما نُسخ مع نص أو ملف، وكل ما يعلّمه مدير كلمات المرور بأنه خاص.</li>
<li><strong>إذن تسهيلات الاستخدام</strong> يسمح لزر الإرسال بلصق اللقطة في التطبيق الذي تستخدمه، بالضغط على ⌘V هناك. ولا يستخدمه Snapfly لأي شيء آخر. ويمكنك إيقافه في أي وقت من إعدادات النظام › الخصوصية والأمن › تسهيلات الاستخدام.</li>
<li><strong>إذن تسجيل الشاشة</strong> يسمح لـ Snapfly بالتقاط اللقطات والتسجيلات التي تطلبها، بـ <bdi dir="ltr">⌃⌥S</bdi> أو زر التصوير أو «تسجيل الشاشة». لا يلتقط شيئًا إلا حين تطلب، وما يلتقطه يبقى على جهازك.</li>
<li><strong>المتصفحات.</strong> كي يظهر زر الإرسال على مواقع الدردشة وحدها، يسأل Snapfly المتصفح الذي أمامك عن عنوان الصفحة المفتوحة، بعد أن تسمح له. وحين يكون ختم الوقت مفعّلًا، يكتب هذا العنوان أيضًا على ختم اللقطة الجديدة، ويبقى معها على جهازك. ولا يقرأ من المتصفح شيئًا آخر.</li>
<li>تعرض الإعدادات › الأذونات كل إذن منها، وهل هو مسموح، وكيف تغيّره.</li>
<li><strong>إعداداتك</strong>، مثل شكل الحبل وما يُغطّى، تُحفظ على جهازك فقط.</li>
</ul>"""),
        ("خدمات Apple",
         """<p>تستخدم «ترجمة النص» ترجمة Apple على جهازك، وقد ينزّل macOS ملفات لغة من Apple لذلك. ويستخدم «وصف ذكي»، و«إخفاء جزء» حين تقول بجملة ما تريد إخفاءه، Apple Intelligence على جهازك. وحين تحصل على Snapfly من Mac App Store أو TestFlight، تتولّى Apple ذلك وفق سياسة الخصوصية الخاصة بها. وإن وافقت على مشاركة التحليلات مع مطوّري التطبيقات، فقد تعطينا Apple تقارير أعطال وإحصاءات استخدام مجهولة الهوية، نستخدمها فقط لإصلاح المشكلات. انظر <a href="https://www.apple.com/legal/privacy/">سياسة خصوصية Apple</a>.</p>"""),
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
        ("كيف ألتقط لقطة شاشة بـ Snapfly؟",
         """<p>اضغط <bdi class="chord" dir="ltr"><kbd>⌃</kbd><kbd>⌥</kbd><kbd>S</kbd></bdi>، أو انقر زر التصوير عند حافة الشاشة. ثم اسحب فوق منطقة، أو انقر نافذة، أو اضغط Return لالتقاط الشاشة كلها. تُعلَّق اللقطة على الحبل فورًا. وفي المرة الأولى يطلب منك macOS السماح لـ Snapfly بتسجيل الشاشة.</p>
<p>ولالتقاط قائمة تُغلق حين تنقر، اختر «التقاط صورة للشاشة بمؤقت» من قائمة Snapfly في شريط القوائم، واختر عدد الثواني، ثم افتح القائمة قبل أن ينتهي العد.</p>"""),
        ("كيف أسجّل الشاشة؟",
         """<p>اختر «تسجيل الشاشة» من قائمة Snapfly في شريط القوائم، أو اضغط <bdi class="chord" dir="ltr"><kbd>⌃</kbd><kbd>⌥</kbd><kbd>R</kbd></bdi>. اسحب فوق منطقة أو انقر نافذة. وللإيقاف انقر الزر الأحمر في أسفل الشاشة. يُعلَّق التسجيل على الحبل؛ اضغط عليه مطوّلًا واختر «إنشاء GIF» لتحوّله إلى صورة GIF.</p>"""),
        ("هل أستطيع إرسال رسالة مع الصور؟",
         """<p>اضغط مطوّلًا على زر الإرسال فوق الدردشة، أو انقره بالزر الأيمن واختر «إرسال مع رسالة…». اكتب رسالتك واضغط Return: تذهب الصور أولًا، ثم كلماتك.</p>"""),
        ("كيف أغيّر ترتيب الصور على الحبل؟",
         """<p>اسحب اللقطة يمينًا أو يسارًا على طول الحبل. و«إرسال الكل» و«نسخ الكل» يحافظان على هذا الترتيب. ومع VoiceOver استخدم «نقل إلى الأمام» و«نقل إلى الخلف».</p>"""),
        ("كيف أرسل لقطة إلى دردشة؟",
         """<p>انقر في خانة الكتابة في الدردشة، ثم انقر الطائرة الورقية على اللقطة. أو اضغط <bdi class="chord" dir="ltr"><kbd>⌃</kbd><kbd>⌥</kbd><kbd>V</kbd></bdi> لإرسال أحدث لقطة. ولإرسال عدة لقطات معًا، انقرها أولًا وأنت ضاغط على ⌘.</p>"""),
        ("زر الإرسال يقول «غير مسموح بعد».",
         """<p>عند الإرسال يضغط Snapfly ⌘V نيابة عنك، ولذلك يطلب macOS إذن تسهيلات الاستخدام. وفي Snapfly تعرض الإعدادات › الأذونات كل إذن يستخدمه، وهل هو مسموح، وزرًّا واحدًا للسماح به.</p>
<ol>
<li>افتح إعدادات النظام › الخصوصية والأمن › تسهيلات الاستخدام.</li>
<li>إن كان Snapfly في القائمة، فشغّله.</li>
<li>إن لم يكن، انقر +، واختر Snapfly من «التطبيقات»، وانقر «فتح»، ثم شغّله.</li>
<li>أغلق Snapfly وافتحه من جديد.</li>
</ol>"""),
        ("كيف أصنع ملف PDF؟",
         """<p>اضغط مطوّلًا على اللقطة، أو انقرها بالزر الأيمن، واختر «إنشاء PDF». ولوضع عدة لقطات في ملف واحد، انقرها أولًا وأنت ضاغط على ⌘، ثم انقر زر PDF على اللافتة في آخر الحبل.</p>"""),
        ("كيف أغطّي المعلومات الخاصة؟",
         """<p>افتح الإعدادات › الخصوصية واختر ما يُغطّى. ولتغطية شيء فاتته التغطية، اضغط مطوّلًا على اللقطة واختر «إخفاء جزء…»، ثم اسحب فوقه أو قل ما تريد إخفاءه، مثل «كل شيء ما عدا المبلغ والتاريخ».</p>"""),
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
