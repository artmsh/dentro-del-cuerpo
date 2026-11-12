//! Dra. Elena Marín: the atlas of things she can identify, and the queue that turns game events into
//! subtitles. State-driven; no generation at runtime. Every line is held in all languages at once, so the
//! language can change while she is speaking.

const std = @import("std");
const Text = @import("i18n.zig").Text;
const bindings = @import("bindings.zig");

pub const Topic = enum(u8) {
    red_cell,
    platelet,
    vein_wall,
    cannula,
    leaflet,
    sinus,
    neutrophil,
    staph,
    nest,
    anchor,
    thrombus,
    embolus,
    septum,
    phlebolith,
    transit,
    reticulocyte,
    band_cell,
    nucleated_red_cell,
    // chapter 2: jejunum
    villus,
    villus_tip,
    crypt,
    blunted_villus,
    contraction,
    lipid_droplet,
    unknown_microbe,
    infected_cell,
    shed_cell,
    rotavirus,
    commensal,
    viral_factory,

    pub const count = @typeInfo(Topic).@"enum".field_names.len;
};

pub const Entry = struct {
    name: Text,
    size: Text,
    /// One line, said on first identification.
    short: Text,
    /// Said when the pilot asks again.
    deep: Text,
    hostile: bool = false,
};

pub fn entry(t: Topic) Entry {
    return switch (t) {
        .red_cell => .{
            .name = .{ .en = "Erythrocyte", .uk = "Еритроцит" },
            .size = .{ .en = "7.8 µm", .uk = "7,8 мкм" },
            .short = .{
                .en = "Erythrocyte — a red blood cell. 7.8 microns: about your size.",
                .uk = "Еритроцит — червона клітина крові. 7,8 мікрона: приблизно як ви.",
            },
            .deep = .{
                .en = "No nucleus, just haemoglobin in a dimpled disc. The dimple adds surface for gas exchange and lets the cell fold through capillaries narrower than itself. There are five million in every microlitre; your display hides ninety-nine in a hundred or you would see nothing else. These are dark because venous blood has already given up its oxygen.",
                .uk = "Ядра немає — лише гемоглобін у двоввігнутому диску. Увігнутість збільшує поверхню для газообміну й дає клітині змогу складатися, проходячи капілярами, вужчими за неї саму. У кожному мікролітрі їх п’ять мільйонів; ваш дисплей приховує дев’яносто дев’ять зі ста, інакше ви не бачили б нічого іншого. Ці темні, бо венозна кров уже віддала свій кисень.",
            },
        },
        .platelet => .{
            .name = .{ .en = "Platelet", .uk = "Тромбоцит" },
            .size = .{ .en = "2–3 µm", .uk = "2–3 мкм" },
            .short = .{
                .en = "Platelet. A cell fragment that plugs breaks in the vessel wall.",
                .uk = "Тромбоцит. Фрагмент клітини, що закриває пошкодження судинної стінки.",
            },
            .deep = .{
                .en = "Shed by megakaryocytes in the bone marrow. Where endothelium is injured they stick, change shape and call in fibrin. That is why every stray round into the wall costs the patient: you start the clotting we came to remove.",
                .uk = "Їх відшнуровують мегакаріоцити в кістковому мозку. Там, де ендотелій ушкоджено, вони прилипають, змінюють форму і скликають фібрин. Тому кожен заряд, що випадково влучив у стінку, дорого обходиться пацієнтці: ви запускаєте те саме згортання, яке ми прийшли усунути.",
            },
        },
        .vein_wall => .{
            .name = .{ .en = "Endothelium", .uk = "Ендотелій" },
            .size = .{ .en = "wall 3.6 mm across", .uk = "вена 3,6 мм у діаметрі" },
            .short = .{
                .en = "Endothelium. The vein's lining, one cell thick.",
                .uk = "Ендотелій. Вистилка вени завтовшки в одну клітину.",
            },
            .deep = .{
                .en = "Each cobble is one endothelial cell, stretched along the flow. Intact endothelium is the one surface in the body that blood will not clot on; scrape it and platelets arrive in seconds. This vein is 3.6 millimetres across — four hundred and fifty of your hulls.",
                .uk = "Кожен камінець цієї бруківки — одна ендотеліальна клітина, витягнута вздовж течії. Неушкоджений ендотелій — єдина поверхня в тілі, на якій кров не згортається; подряпайте його — і за лічені секунди з’являться тромбоцити. Ця вена має 3,6 міліметра в діаметрі — чотириста п’ятдесят ваших корпусів.",
            },
        },
        .cannula => .{
            .name = .{ .en = "Cannula", .uk = "Канюля" },
            .size = .{ .en = "22 G, bore 0.41 mm", .uk = "22 G, просвіт 0,41 мм" },
            .short = .{
                .en = "Our cannula. 22 gauge. That is how you got in.",
                .uk = "Наша канюля. 22 G. Через неї ви сюди й потрапили.",
            },
            .deep = .{
                .en = "A steel tube ground to a long bevel so it parts the vein wall instead of coring it. To you it is a tunnel fifty hulls wide. I am holding the other end; there is nothing for you back up there.",
                .uk = "Сталева трубка, заточена довгим скосом, щоб розсувати стінку вени, а не вирізати з неї стовпчик. Для вас це тунель завширшки п’ятдесят корпусів. Другий її кінець тримаю я; там, нагорі, вам робити нічого.",
            },
        },
        .leaflet => .{
            .name = .{ .en = "Valve cusp", .uk = "Стулка клапана" },
            .size = .{ .en = "cusp ~2 mm long", .uk = "стулка ~2 мм завдовжки" },
            .short = .{
                .en = "Valve cusp. It lets blood climb the leg and stops it falling back.",
                .uk = "Стулка клапана. Вона пропускає кров угору по нозі й не дає їй падати назад.",
            },
            .deep = .{
                .en = "Leg veins work against gravity. Calf muscle squeezes blood upward; when the muscle relaxes the blood tries to fall, fills the pockets behind the two cusps and presses them shut. Read the cusps and you have read the flow: against the wall means forward flow, meeting in the middle means reflux.",
                .uk = "Вени ніг працюють проти сили тяжіння. Литковий м’яз витискає кров угору; коли він розслабляється, кров намагається впасти, заповнює кишені за двома стулками й притискає їх одну до одної. Прочитайте стулки — і ви прочитали потік: притиснуті до стінки — кров тече вперед, зімкнені посередині — рефлюкс.",
            },
        },
        .sinus => .{
            .name = .{ .en = "Valve sinus", .uk = "Синус клапана" },
            .size = .{ .en = "bulge +30 %", .uk = "випин +30 %" },
            .short = .{
                .en = "Valve sinus. The wall bulges to make room for the pocket behind a cusp.",
                .uk = "Синус клапана. Стінка випинається, щоб дати місце кишені за стулкою.",
            },
            .deep = .{
                .en = "The bulge is how you spot a valve from a distance. Behind the cusp the blood barely moves; it turns in a slow vortex. Stagnant blood is where a thrombus starts, which is why deep-vein clots begin in valve pockets.",
                .uk = "За цим випином клапан видно здалеку. За стулкою кров майже не рухається — лише повільно обертається у вирі. Тромб зароджується саме в застійній крові, тому тромбози глибоких вен починаються в кишенях клапанів.",
            },
        },
        .neutrophil => .{
            .name = .{ .en = "Neutrophil", .uk = "Нейтрофіл" },
            .size = .{ .en = "12 µm", .uk = "12 мкм" },
            .short = .{
                .en = "Neutrophil. White cell, first responder to bacteria. On our side.",
                .uk = "Нейтрофіл. Лейкоцит, що першим реагує на бактерії. На нашому боці.",
            },
            .deep = .{
                .en = "They leave the fast core and roll along the wall on selectin bonds, waiting for the signal to squeeze through into tissue. That is margination, and the squeeze is the trick your diapedesis frame copies. More rolling cells means inflammation close by: follow where they thicken.",
                .uk = "Вони полишають швидку середину потоку й котяться по стінці на селектинових зв’язках, чекаючи сигналу протиснутися крізь неї в тканину. Це маргінація, а протискування — той самий трюк, який копіює ваш діапедезний каркас. Більше клітин котиться — отже, запалення близько: рухайтеся туди, де їх густішає.",
            },
        },
        .staph => .{
            .name = .{ .en = "Staphylococcus aureus", .uk = "Staphylococcus aureus" },
            .size = .{ .en = "cocci 1 µm, cluster ~5 µm", .uk = "коки 1 мкм, скупчення ~5 мкм" },
            .short = .{
                .en = "Staphylococcus aureus. Cocci in clusters. Hostile.",
                .uk = "Staphylococcus aureus, золотистий стафілокок. Коки у скупченнях. Ворог.",
            },
            .deep = .{
                .en = "Staphyle is Greek for a bunch of grapes. It secretes coagulase, which turns the patient's own fibrinogen into a fibrin coat: it builds clots to hide in. On your display a cluster glows gold before it lunges; that glow is your cue. The lunge is our threat model — real cocci only drift.",
                .uk = "«Стафіле» грецькою — гроно винограду. Він виділяє коагулазу, що перетворює власний фібриноген пацієнтки на фібринову оболонку: він будує згустки, щоб у них ховатися. На вашому дисплеї скупчення спалахує золотом перед кидком — це ваш сигнал. Кидок — наша модель загрози: справжні коки лише дрейфують.",
            },
            .hostile = true,
        },
        .nest => .{
            .name = .{ .en = "Biofilm colony", .uk = "Колонія в біоплівці" },
            .size = .{ .en = "dome ~90 µm", .uk = "купол ~90 мкм" },
            .short = .{
                .en = "Biofilm. A colony under a slime of sugars and fibrin.",
                .uk = "Біоплівка. Колонія під слизом із цукрів і фібрину.",
            },
            .deep = .{
                .en = "The matrix soaks up antibiotics and our lytic rounds alike. The only way in is mechanical: hold the drill in the slime to open it, and put rounds through the opening with your other arm before it closes again.",
                .uk = "Матрикс поглинає і антибіотики, і наші літичні заряди. Єдиний шлях усередину — механічний: тримайте свердло в слизу, щоб розкрити його, і другою рукою стріляйте в отвір, поки він не затягнувся.",
            },
            .hostile = true,
        },
        .anchor => .{
            .name = .{ .en = "Fibrin cable", .uk = "Фібриновий тяж" },
            .size = .{ .en = "~0.5 mm long", .uk = "~0,5 мм завдовжки" },
            .short = .{
                .en = "Fibrin cable. Clot protein tying the thrombus down.",
                .uk = "Фібриновий тяж. Білок згустку, яким тромб прив’язаний до місця.",
            },
            .deep = .{
                .en = "Fibrin is the mesh in every clot. Fresh fibrin dissolves; cross-linked, and here re-knit by coagulase, it has to be cut. The drill cuts it. While any colony lives, it re-knits what you cut.",
                .uk = "Фібрин — це сітка в кожному згустку. Свіжий фібрин розчиняється; зшитий, а тут іще й зарощений коагулазою, доводиться різати. Його ріже свердло. Поки жива хоч одна колонія, вона зрощує те, що ви перерізали.",
            },
        },
        .thrombus => .{
            .name = .{ .en = "Thrombus", .uk = "Тромб" },
            .size = .{ .en = "0.7 mm", .uk = "0,7 мм" },
            .short = .{
                .en = "Thrombus. Red cells and platelets in a fibrin mesh, lodged in the valve pocket.",
                .uk = "Тромб. Еритроцити й тромбоцити у фібриновій сітці, що застрягли в кишені клапана.",
            },
            .deep = .{
                .en = "Too small for the ultrasound to have caught, large enough to pin the cusp. Do not punch or drill the body: what breaks off travels to the lungs. Cut it loose first, then dissolve it.",
                .uk = "Замалий, щоб його помітило УЗД, але достатньо великий, щоб затиснути стулку. Не бийте й не свердліть його тіло: те, що відколеться, полетить у легені. Спершу відріжте його від кріплень, потім розчиніть.",
            },
        },
        .embolus => .{
            .name = .{ .en = "Embolus", .uk = "Ембол" },
            .size = .{ .en = "20–30 µm", .uk = "20–30 мкм" },
            .short = .{ .en = "Embolus — a piece of clot loose in the flow.", .uk = "Ембол — шматок згустку, що вільно пливе в потоці." },
            .deep = .{
                .en = "It rides the vena cava to the right heart and lodges in the first lung artery narrower than itself. Lytic rounds dissolve it. A punch only makes two.",
                .uk = "Порожнистою веною він дістається правих відділів серця й застрягає в першій легеневій артерії, вужчій за нього. Літичні заряди його розчиняють. Удар лише зробить з одного два.",
            },
            .hostile = true,
        },
        .septum => .{
            .name = .{ .en = "Post-thrombotic web", .uk = "Посттромботична перетинка" },
            .size = .{ .en = "spans the lumen", .uk = "перекриває просвіт" },
            .short = .{
                .en = "Post-thrombotic web. Scar from an old clot, grown across the vein.",
                .uk = "Посттромботична перетинка. Рубець від старого тромбу, що виріс упоперек вени.",
            },
            .deep = .{
                .en = "A thrombus the body cannot clear is organised into fibrous tissue. This one left a single channel. It is why this leg has been swelling for years.",
                .uk = "Тромб, який організм не може розсмоктати, проростає сполучною тканиною. Цей залишив єдиний канал. Ось чому ця нога набрякає роками.",
            },
        },
        .phlebolith => .{
            .name = .{ .en = "Phlebolith", .uk = "Флеболіт" },
            .size = .{ .en = "0.38 mm", .uk = "0,38 мм" },
            .short = .{
                .en = "Phlebolith. A vein stone: old thrombus turned to calcium.",
                .uk = "Флеболіт. Венозний камінь: старий тромб, що звапнів.",
            },
            .deep = .{
                .en = "Calcium phosphate — hard and brittle. Rounds do nothing and the drill skates. It breaks on impact, and only when both arms land together.",
                .uk = "Фосфат кальцію — твердий і крихкий. Заряди його не беруть, а свердло зісковзує. Він ламається від удару, і лише тоді, коли обидві руки б’ють разом.",
            },
        },
        .transit => .{
            .name = .{ .en = "Transit marker", .uk = "Транзитний маркер" },
            .size = .{ .en = "display overlay", .uk = "елемент дисплея" },
            .short = .{
                .en = "Transit marker. Mine. Fly through it and I take the flow from there.",
                .uk = "Транзитний маркер. Мій. Пролетіть крізь нього — далі вас поведу я.",
            },
            .deep = .{
                .en = "Between stations I drop your tempo link from one-in-a-hundred to real time and let the blood carry you. Three seconds for you is twelve centimetres of vein.",
                .uk = "Між станціями я перемикаю ваш масштаб часу з одного до ста на реальний і даю крові вас нести. Три секунди для вас — це дванадцять сантиметрів вени.",
            },
        },
        .reticulocyte => .{
            .name = .{ .en = "Reticulocyte", .uk = "Ретикулоцит" },
            .size = .{ .en = "8.5 µm", .uk = "8,5 мкм" },
            .short = .{
                .en = "Odd. A reticulocyte — a red cell one day out of the marrow, still carrying RNA.",
                .uk = "Дивно. Ретикулоцит — еритроцит, що лише добу як вийшов із кісткового мозку й досі несе РНК.",
            },
            .deep = .{
                .en = "Normally one red cell in a hundred. The mottling is leftover ribosomes; it will be gone in a day. Seeing them easily means the marrow is pushing cells out early.",
                .uk = "У нормі — один еритроцит зі ста. Плямистість — це залишки рибосом; за добу вона зникне. Якщо вони легко трапляються на очі, кістковий мозок випускає клітини передчасно.",
            },
        },
        .band_cell => .{
            .name = .{ .en = "Band neutrophil", .uk = "Паличкоядерний нейтрофіл" },
            .size = .{ .en = "13 µm", .uk = "13 мкм" },
            .short = .{
                .en = "Band neutrophil. Immature: the nucleus is still a horseshoe. Released early.",
                .uk = "Паличкоядерний нейтрофіл. Незрілий: ядро ще має форму підкови. Випущений завчасно.",
            },
            .deep = .{
                .en = "A mature neutrophil's nucleus has three to five lobes. Bands in the blood are a left shift: the marrow emptying its reserve because the infection is using neutrophils faster than they mature.",
                .uk = "У зрілого нейтрофіла ядро має від трьох до п’яти сегментів. Паличкоядерні в крові — це зсув формули вліво: кістковий мозок спорожнює резерв, бо інфекція витрачає нейтрофіли швидше, ніж вони дозрівають.",
            },
        },
        .nucleated_red_cell => .{
            .name = .{ .en = "Nucleated red cell", .uk = "Ядровмісний еритроцит" },
            .size = .{ .en = "9 µm", .uk = "9 мкм" },
            .short = .{
                .en = "A red cell with its nucleus still in it. That should never be out here.",
                .uk = "Еритроцит, що досі не позбувся ядра. Тут його не мало б бути ніколи.",
            },
            .deep = .{
                .en = "Erythroblasts eject their nucleus before they leave the marrow. One in the circulation of an adult means the marrow is under severe stress.",
                .uk = "Еритробласти викидають ядро ще до виходу з кісткового мозку. Один такий у кровотоці дорослої людини означає, що кістковий мозок працює на межі можливостей.",
            },
        },
        .villus => .{
            .name = .{ .en = "Villus", .uk = "Ворсинка" },
            .size = .{ .en = "0.8 mm tall", .uk = "0,8 мм заввишки" },
            .short = .{
                .en = "A villus. One finger of the gut lining; everything she eats is absorbed through these.",
                .uk = "Ворсинка. Один палець кишкової вистилки; усе, що вона їсть, всмоктується крізь них.",
            },
            .deep = .{
                .en = "Each cobble is an enterocyte, and each enterocyte carries three thousand microvilli of its own: fold on fold, the small intestine reaches the area of a studio flat. Inside the finger are a capillary loop for sugars and amino acids and one blind lymph vessel, the lacteal, for fat. You came up that capillary.",
                .uk = "Кожен камінець цієї бруківки — ентероцит, і кожен ентероцит несе три тисячі власних мікроворсинок: складка на складці, тонка кишка сягає площі невеликої квартири. Усередині пальця — капілярна петля для цукрів та амінокислот і одна сліпа лімфатична судина, молочна, для жирів. Цим капіляром ви сюди й піднялися.",
            },
        },
        .villus_tip => .{
            .name = .{ .en = "Villus tip", .uk = "Верхівка ворсинки" },
            .size = .{ .en = "extrusion zone", .uk = "зона екструзії" },
            .short = .{
                .en = "The tip. Cells are born in the crypts, climb for four days and are pushed out here.",
                .uk = "Верхівка. Клітини народжуються в криптах, чотири дні підіймаються і тут виштовхуються назовні.",
            },
            .deep = .{
                .en = "The lining replaces itself every four to five days. At the tip a worn-out cell is squeezed out by its neighbours, which close the gap underneath it before it leaves, so the barrier never opens. Rotavirus infects exactly these mature cells. If you push an infected one out the way the gut would, the sheet seals behind it.",
                .uk = "Вистилка оновлюється кожні чотири-п’ять днів. На верхівці зношену клітину витискають сусіди, які змикають щілину під нею ще до того, як вона вийде, тож бар’єр ніколи не відкривається. Ротавірус заражає саме ці зрілі клітини. Якщо виштовхнути заражену так, як це зробила б сама кишка, пласт за нею зімкнеться.",
            },
        },
        .crypt => .{
            .name = .{ .en = "Crypt mouths", .uk = "Устя крипт" },
            .size = .{ .en = "pits 50 µm apart", .uk = "ямки за 50 мкм одна від одної" },
            .short = .{
                .en = "Crypts of Lieberkühn. Stem cells sit at the bottom of each pit; this floor is the nursery.",
                .uk = "Крипти Ліберкюна. На дні кожної ямки сидять стовбурові клітини; це дно — розплідник.",
            },
            .deep = .{
                .en = "A crypt makes about three hundred cells a day and sends them up the neighbouring villi. Nothing digests down here and almost nothing flows, which makes it the one place a contraction ring cannot reach you. Do not fire into it: the stem cells are what will rebuild whatever the virus strips.",
                .uk = "Одна крипта виробляє близько трьохсот клітин на добу й відправляє їх угору сусідніми ворсинками. Тут, унизу, ніщо не перетравлюється і майже ніщо не тече, тож це єдине місце, де кільце скорочення вас не дістане. Не стріляйте сюди: саме стовбурові клітини відбудують усе, що обдере вірус.",
            },
        },
        .blunted_villus => .{
            .name = .{ .en = "Blunted villus", .uk = "Сплощена ворсинка" },
            .size = .{ .en = "0.15 mm stub", .uk = "пеньок 0,15 мм" },
            .short = .{
                .en = "That was a villus. The virus killed the tip cells faster than the crypts could replace them.",
                .uk = "Це була ворсинка. Вірус убивав клітини верхівки швидше, ніж крипти встигали їх заміняти.",
            },
            .deep = .{
                .en = "Villus blunting. With the absorbing cells gone, sugar stays in the lumen and drags water after it, and the viral toxin NSP4 makes the crypts secrete on top of that. This stretch is why she has lost three litres since yesterday. It grows back within a week once the virus is cleared.",
                .uk = "Атрофія ворсинок. Без клітин, що всмоктують, цукор лишається в просвіті й тягне за собою воду, а вірусний токсин NSP4 ще й змушує крипти виділяти рідину. Через цю ділянку вона від учора втратила три літри. Щойно вірус буде усунено, все відросте за тиждень.",
            },
        },
        .contraction => .{
            .name = .{ .en = "Contraction ring", .uk = "Кільце скорочення" },
            .size = .{ .en = "travels at 1–2 cm/s", .uk = "рухається зі швидкістю 1–2 см/с" },
            .short = .{
                .en = "That is the opposite wall coming down. A peristaltic ring: the gut is squeezing shut around you.",
                .uk = "Це опускається протилежна стінка. Перистальтичне кільце: кишка стискається довкола вас.",
            },
            .deep = .{
                .en = "Circular muscle contracts behind the contents and relaxes ahead of them, so the ring always travels away from the mouth. It closes the lumen down to the villus tips; the villi mesh like the bristles of two brushes and the spaces between them stay open. The ring cannot hurt you between the villi. On top of one it can.",
                .uk = "Коловий м’яз скорочується позаду вмісту й розслабляється попереду нього, тож кільце завжди рухається геть від рота. Воно змикає просвіт до верхівок ворсинок; ворсинки заходять одна між одну, як щетинки двох щіток, а проміжки між ними лишаються відкритими. Між ворсинками кільце вам не зашкодить. На верхівці — може.",
            },
            .hostile = true,
        },
        .lipid_droplet => .{
            .name = .{ .en = "Fat droplet", .uk = "Жирова крапля" },
            .size = .{ .en = "1–10 µm", .uk = "1–10 мкм" },
            .short = .{
                .en = "Emulsified fat. Bile salts have broken her breakfast into droplets.",
                .uk = "Емульгований жир. Жовчні солі роздрібнили її сніданок на краплі.",
            },
            .deep = .{
                .en = "Pancreatic lipase works on the surface of these, shaving them into fatty acids that travel in micelles two hundred times smaller. The bile that made this emulsion was stored in the gallbladder; we will see where it comes from.",
                .uk = "На їхній поверхні працює панкреатична ліпаза, зістругуючи з них жирні кислоти, що мандрують далі в міцелах, у двісті разів дрібніших. Жовч, яка створила цю емульсію, зберігалася в жовчному міхурі; ми ще побачимо, звідки вона береться.",
            },
        },
        .unknown_microbe => .{
            .name = .{ .en = "Unresolved", .uk = "Не розпізнано" },
            .size = .{ .en = "under 5 µm", .uk = "менше 5 мкм" },
            .short = .{
                .en = "Too small to call from its outline. Scan before you shoot: most of what lives here is on her side.",
                .uk = "Надто дрібне, щоб визначити за обрисом. Скануйте, перш ніж стріляти: більшість тутешніх мешканців — на її боці.",
            },
            .deep = .{
                .en = "There are more bacteria in her gut than cells in her body, and nearly all of them are working for her. At this size a virus-laden bleb and a commensal rod look the same until the scan reads their surface.",
                .uk = "У її кишківнику бактерій більше, ніж клітин у її тілі, і майже всі вони працюють на неї. За такого розміру везикула з вірусом і паличка-коменсал виглядають однаково, доки скан не зчитає їхню поверхню.",
            },
        },
        .infected_cell => .{
            .name = .{ .en = "Infected enterocyte", .uk = "Заражений ентероцит" },
            .size = .{ .en = "swollen, 18 µm", .uk = "набряклий, 18 мкм" },
            .short = .{
                .en = "Infected enterocyte: swollen, full of virus. Punch it out of the sheet. Do not burst it where it sits.",
                .uk = "Заражений ентероцит: набряклий, повний вірусу. Вибийте його з пласта. Не розривайте там, де він сидить.",
            },
            .deep = .{
                .en = "The virus has turned the cell into a replication site; rupture it in place and thousands of particles land on its neighbours. A firm push from the lumen side makes the neighbours do what they do at the tip anyway: squeeze it out and seal the gap. Once it is free in the lumen, destroy it before it bursts on its own.",
                .uk = "Вірус перетворив клітину на осередок реплікації; розірвіть її на місці — і тисячі частинок осядуть на сусідах. Упевнений поштовх із боку просвіту змушує сусідів зробити те, що вони й так роблять на верхівці: витиснути її та зімкнути щілину. Щойно вона опиниться в просвіті, знищте її, перш ніж вона лусне сама.",
            },
            .hostile = true,
        },
        .shed_cell => .{
            .name = .{ .en = "Shed infected cell", .uk = "Відторгнута заражена клітина" },
            .size = .{ .en = "16 µm", .uk = "16 мкм" },
            .short = .{
                .en = "That one is out. It will burst in a few seconds. Shoot it first.",
                .uk = "Ця вже зовні. За кілька секунд вона лусне. Встигніть вистрілити раніше.",
            },
            .deep = .{
                .en = "A dying infected cell releases its virus by lysis. Your rounds carry a protease load that destroys the particles along with the cell; left alone it scatters them over the nearest villi.",
                .uk = "Гинучи, заражена клітина вивільняє вірус через лізис. Ваші заряди несуть протеази, що руйнують частинки разом із клітиною; якщо її не чіпати, вона розсіє їх по найближчих ворсинках.",
            },
            .hostile = true,
        },
        .rotavirus => .{
            .name = .{ .en = "Rotavirus bleb", .uk = "Везикула з ротавірусом" },
            .size = .{ .en = "3 µm cluster of 70 nm particles", .uk = "скупчення 3 мкм із частинок по 70 нм" },
            .short = .{
                .en = "Rotavirus, travelling in a membrane bleb. It is looking for a healthy tip. One round.",
                .uk = "Ротавірус, що подорожує в мембранній везикулі. Шукає здорову верхівку. Один заряд.",
            },
            .deep = .{
                .en = "Single particles are seventy nanometres, far below your optics; what you see is a vesicle packed with them, which is how the virus really spreads between cells. Each wheel-shaped particle carries eleven segments of double-stranded RNA. A bleb that reaches a mature enterocyte infects it, and you will not see that cell again until you scan.",
                .uk = "Окремі частинки мають сімдесят нанометрів — це далеко за межами вашої оптики; ви бачите напхану ними везикулу, і саме так вірус насправді поширюється між клітинами. Кожна частинка, схожа на колесо, несе одинадцять сегментів дволанцюгової РНК. Везикула, що дісталася зрілого ентероцита, заражає його, і ви не побачите цієї клітини, доки не проскануєте.",
            },
            .hostile = true,
        },
        .commensal => .{
            .name = .{ .en = "Commensal bacteria", .uk = "Коменсальні бактерії" },
            .size = .{ .en = "2–4 µm rods", .uk = "палички 2–4 мкм" },
            .short = .{ .en = "Commensals. Hers. Leave them alone.", .uk = "Коменсали. Її власні. Не чіпайте їх." },
            .deep = .{
                .en = "Bacteroides and lactobacilli. They ferment what she cannot digest, make vitamin K, train her immune system and occupy the surfaces a pathogen would need. Every one you kill is ground handed to the next infection.",
                .uk = "Бактероїди й лактобацили. Вони зброджують те, що вона не може перетравити, синтезують вітамін K, тренують її імунну систему й займають поверхні, які знадобилися б патогенові. Кожна вбита вами — це територія, віддана наступній інфекції.",
            },
        },
        .viral_factory => .{
            .name = .{ .en = "Viroplasm dome", .uk = "Купол віроплазми" },
            .size = .{ .en = "0.12 mm", .uk = "0,12 мм" },
            .short = .{
                .en = "A whole tip fused into one infected mass, capped in mucus. Rounds will not get through the cap.",
                .uk = "Ціла верхівка злилася в одну заражену масу під шапкою слизу. Заряди крізь шапку не пройдуть.",
            },
            .deep = .{
                .en = "Viroplasms are the factories the virus builds inside a cell. Here neighbouring cells have fused around them and the goblet cells have buried the lot in mucus. Drill the cap open and fire into the breach while it is open; it will shed blebs at you the whole time.",
                .uk = "Віроплазми — це фабрики, які вірус будує всередині клітини. Тут сусідні клітини злилися довкола них, а келихоподібні клітини поховали все це під слизом. Розсвердліть шапку й стріляйте в пролом, поки він відкритий; увесь цей час купол кидатиме у вас везикули.",
            },
            .hostile = true,
        },
    };
}

pub const Priority = enum(u8) { chatter, normal, urgent };

const Pending = struct { text: Text, prio: Priority };

/// Subtitle queue. Urgent lines interrupt; chatter is dropped when she is already talking.
pub const Voice = struct {
    current: ?Text = null,
    urgent: bool = false,
    remaining: f32 = 0,
    age: f32 = 0,
    queue: [12]Pending = undefined,
    len: usize = 0,
    /// Incremented whenever a new line starts (the audio layer plays a comm chirp on change).
    serial: u32 = 0,

    pub fn say(v: *Voice, text: Text, prio: Priority) void {
        switch (prio) {
            .urgent => {
                // drop queued chatter, keep queued instructions
                var n: usize = 0;
                for (v.queue[0..v.len]) |p| {
                    if (p.prio != .chatter) {
                        v.queue[n] = p;
                        n += 1;
                    }
                }
                v.len = n;
                v.start(text, true);
            },
            .normal => {
                if (v.current == null) {
                    v.start(text, false);
                } else if (v.len < v.queue.len) {
                    v.queue[v.len] = .{ .text = text, .prio = prio };
                    v.len += 1;
                }
            },
            .chatter => {
                if (v.current == null and v.len == 0) v.start(text, false);
            },
        }
    }

    fn start(v: *Voice, text: Text, urgent: bool) void {
        v.current = text;
        v.urgent = urgent;
        v.age = 0;
        v.remaining = holdTime(text, urgent);
        v.serial +%= 1;
    }

    /// Time a line stays up: a base plus reading time per character of the longest version of it any
    /// player can be shown, so the simulation's timing is the same whichever language is in use and
    /// whichever device the prompts are for.
    pub fn holdTime(text: Text, urgent: bool) f32 {
        const base: f32 = if (urgent) 1.6 else 2.2;
        return base + @as(f32, @floatFromInt(bindings.readingLength(text))) * 0.052;
    }

    pub fn update(v: *Voice, dt: f32) void {
        if (v.current == null) return;
        v.age += dt;
        v.remaining -= dt;
        if (v.remaining <= 0) {
            v.current = null;
            if (v.len > 0) {
                const p = v.queue[0];
                for (1..v.len) |i| v.queue[i - 1] = v.queue[i];
                v.len -= 1;
                v.start(p.text, p.prio == .urgent);
            }
        }
    }

    /// Finish the current line now (the pilot pressed "skip").
    pub fn skip(v: *Voice) void {
        if (v.current != null) v.remaining = 0;
    }

    pub fn busy(v: *const Voice) bool {
        return v.current != null or v.len > 0;
    }

    pub fn clear(v: *Voice) void {
        v.current = null;
        v.len = 0;
    }

    /// The objective changed: lines still queued belong to the old one, and the line being spoken is cut
    /// short so the new instruction is not heard late.
    pub fn supersede(v: *Voice) void {
        v.len = 0;
        if (v.current != null and !v.urgent) v.remaining = @min(v.remaining, 1.3);
    }
};

/// Test lines: the queue does not care what a line says.
fn same(s: []const u8) Text {
    return .{ .en = s, .uk = s };
}

test "a stage change drops the lines queued for the old objective" {
    var v: Voice = .{};
    v.say(same("a long instruction for the old objective, still on screen"), .normal);
    v.say(same("stale follow-up"), .normal);
    v.supersede();
    v.say(same("new objective"), .normal);
    try std.testing.expect(v.remaining <= 1.3);
    v.update(1.4);
    try std.testing.expectEqualStrings("new objective", v.current.?.en);
}

test "urgent interrupts and chatter is dropped while talking" {
    var v: Voice = .{};
    v.say(same("first"), .normal);
    v.say(same("second"), .normal);
    v.say(same("idle remark"), .chatter);
    try std.testing.expectEqualStrings("first", v.current.?.en);
    v.say(same("Dodge!"), .urgent);
    try std.testing.expectEqualStrings("Dodge!", v.current.?.en);
    v.update(30);
    try std.testing.expectEqualStrings("second", v.current.?.en);
    v.update(30);
    try std.testing.expect(v.current == null);
}

test "every topic has an entry with a short and a deep line" {
    for (0..Topic.count) |i| {
        const e = entry(@enumFromInt(i));
        inline for (.{ "en", "uk" }) |lang| {
            const name = @field(e.name, lang);
            const short = @field(e.short, lang);
            const deep = @field(e.deep, lang);
            try std.testing.expect(name.len > 0 and @field(e.size, lang).len > 0 and short.len > 0 and deep.len > short.len);
        }
    }
}
