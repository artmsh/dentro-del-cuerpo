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
    // chapter 3: gastric antrum
    gastric_pit,
    surface_mucous_cell,
    mucus_gel,
    gastric_juice,
    antral_wave,
    helicobacter,
    colonised_pit,
    ulcer_margin,
    ulcer_bed,
    bleeding_vessel,
    food_particle,

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
        .gastric_pit => .{
            .name = .{ .en = "Gastric pit", .uk = "Шлункова ямка" },
            .size = .{ .en = "70 µm across, 0.2 mm deep", .uk = "70 мкм завширшки, 0,2 мм завглибшки" },
            .short = .{
                .en = "Gastric pit. The surface dips into a tube, and the glands open into the bottom of it. It is full of gel, and it stays open when the walls meet.",
                .uk = "Шлункова ямка. Поверхня занурюється в трубку, і на її дні відкриваються залози. Ямка повна гелю й лишається відкритою, коли стінки змикаються.",
            },
            .deep = .{
                .en = "A foveola. In the antrum the pits take up half the thickness of the mucosa; the glands under them make mucus and the hormone gastrin rather than acid, which comes from the body of the stomach above. The stem cells sit in the neck where pit meets gland, and from there new surface cells climb up and out in about three days. Do not fire into one.",
                .uk = "Фовеола. В антральному відділі ямки займають половину товщини слизової; залози під ними виробляють слиз і гормон гастрин, а не кислоту — та надходить із тіла шлунка вище. Стовбурові клітини сидять у шийці, де ямка переходить у залозу, і звідти нові поверхневі клітини підіймаються назовні приблизно за три дні. Не стріляйте в ямку.",
            },
        },
        .surface_mucous_cell => .{
            .name = .{ .en = "Surface mucous cells", .uk = "Поверхневі слизові клітини" },
            .size = .{ .en = "cells 20 µm tall", .uk = "клітини 20 мкм заввишки" },
            .short = .{
                .en = "Surface mucous cells. One sheet of them lines the whole stomach, and each one secretes the gel you are flying in.",
                .uk = "Поверхневі слизові клітини. Один їхній шар вистеляє весь шлунок, і кожна виділяє гель, у якому ви летите.",
            },
            .deep = .{
                .en = "Each cell makes mucin and pumps bicarbonate into it, so the gel holds a gradient: neutral against the cells, acid at the lumen. That gradient is the whole defence; the cells themselves would dissolve at pH 2. They are replaced every three to five days. Aspirin and ibuprofen cut the prostaglandins that drive both the mucus and the bicarbonate, which is the other common way to get an ulcer.",
                .uk = "Кожна клітина виробляє муцин і закачує в нього бікарбонат, тож гель тримає градієнт: біля клітин він нейтральний, біля просвіту — кислий. Цей градієнт і є весь захист: самі клітини при pH 2 розчинилися б. Вони оновлюються кожні три-п’ять днів. Аспірин та ібупрофен пригнічують простагландини, від яких залежать і слиз, і бікарбонат, — це другий поширений шлях до виразки.",
            },
        },
        .mucus_gel => .{
            .name = .{ .en = "Mucus gel", .uk = "Слизовий гель" },
            .size = .{ .en = "0.3 mm thick", .uk = "0,3 мм завтовшки" },
            .short = .{
                .en = "The mucus gel. A third of a millimetre of mucin stuck to the lining, neutral at the bottom and acid at the top.",
                .uk = "Слизовий гель. Третина міліметра муцину, що прилип до слизової: знизу нейтральний, згори кислий.",
            },
            .deep = .{
                .en = "Two layers: a firm one that stays on the cells and a loose one that the waves shear off and the cells replace. Bicarbonate from below meets acid from above inside it, and the pH climbs from 2 to 7 over forty times your length. Acid from the glands gets out through it in narrow channels without mixing. Your rounds drag in it. Helicobacter does not: its spiral body turns like a screw, and its ammonia thins the gel around it.",
                .uk = "Два шари: щільний, який тримається на клітинах, і пухкий, який хвилі здирають, а клітини відновлюють. Бікарбонат знизу зустрічається в ньому з кислотою згори, і pH зростає від 2 до 7 на відстані сорока ваших корпусів. Кислота із залоз виходить крізь нього вузькими каналами, не змішуючись. Ваші заряди в ньому в’язнуть. Гелікобактер — ні: його спіральне тіло вгвинчується, як шуруп, а його аміак розріджує гель довкола.",
            },
        },
        .gastric_juice => .{
            .name = .{ .en = "Gastric juice", .uk = "Шлунковий сік" },
            .size = .{ .en = "pH 2, hydrochloric acid", .uk = "pH 2, соляна кислота" },
            .short = .{
                .en = "Gastric juice. Hydrochloric acid at pH 2, with pepsin in it. Your hull is not rated for it.",
                .uk = "Шлунковий сік. Соляна кислота з pH 2 і пепсином. Ваш корпус на це не розрахований.",
            },
            .deep = .{
                .en = "Parietal cells in the body of the stomach pump hydrogen ions against a gradient of a million to one. The acid kills most of what is swallowed and unfolds proteins so that pepsin can cut them. Two litres a day. The stomach does not digest itself only because of the gel, and where the gel fails you get what is ahead of you.",
                .uk = "Парієтальні клітини тіла шлунка качають іони водню проти градієнта мільйон до одного. Кислота вбиває більшість проковтнутого й розгортає білки, щоб пепсин міг їх різати. Два літри на добу. Шлунок не перетравлює сам себе лише завдяки гелю, а там, де гель не впорався, виходить те, що у вас попереду.",
            },
            .hostile = true,
        },
        .antral_wave => .{
            .name = .{ .en = "Antral wave", .uk = "Антральна хвиля" },
            .size = .{ .en = "three a minute", .uk = "три на хвилину" },
            .short = .{
                .en = "That is the opposite wall. An antral wave: here the stomach closes completely to grind what it holds.",
                .uk = "Це протилежна стінка. Антральна хвиля: тут шлунок змикається повністю, щоб перетерти свій вміст.",
            },
            .deep = .{
                .en = "A pacemaker in the stomach wall fires three times a minute and a ring of contraction runs down to the pylorus. The pylorus shuts before the ring arrives, so the contents are squeezed back through the closing ring and sheared: that is how solids are ground to under a millimetre or two before anything is let through. Where the walls meet, only a pit or the ulcer crater stays open.",
                .uk = "Водій ритму в стінці шлунка спрацьовує тричі на хвилину, і кільце скорочення біжить униз до воротаря. Воротар закривається раніше, ніж кільце до нього дійде, тож вміст вичавлюється назад крізь кільце, що змикається, і перетирається: так тверда їжа подрібнюється до частинок, менших за міліметр-два, перш ніж щось пропустять далі. Там, де стінки зійшлися, відкритими лишаються тільки ямки й кратер виразки.",
            },
            .hostile = true,
        },
        .helicobacter => .{
            .name = .{ .en = "Helicobacter pylori", .uk = "Helicobacter pylori" },
            .size = .{ .en = "3 µm spiral rod", .uk = "спіральна паличка 3 мкм" },
            .short = .{
                .en = "Helicobacter pylori. A spiral rod with a tuft of flagella, and the cause of this ulcer.",
                .uk = "Helicobacter pylori. Спіральна паличка з пучком джгутиків — причина цієї виразки.",
            },
            .deep = .{
                .en = "Half the people alive carry it. It survives the stomach by not living in the acid: it drills into the gel and sits against the cells, and its urease splits urea into ammonia, which neutralises acid around it and thins the gel so it can swim. The inflammation it causes weakens the lining for years. Clearing it lets most ulcers heal and stay healed, a finding that earned Marshall and Warren a Nobel prize in 2005.",
                .uk = "Його носить половина людства. У шлунку він виживає тому, що в кислоті не живе: вгвинчується в гель і тримається біля клітин, а його уреаза розщеплює сечовину до аміаку, який нейтралізує кислоту довкола й розріджує гель, щоб у ньому можна було плавати. Запалення, яке він спричиняє, роками ослаблює слизову. Якщо його знищити, більшість виразок гоїться й не повертається — за це відкриття Маршалл і Воррен отримали Нобелівську премію 2005 року.",
            },
            .hostile = true,
        },
        .colonised_pit => .{
            .name = .{ .en = "Colonised pit", .uk = "Колонізована ямка" },
            .size = .{ .en = "plug 50 µm across", .uk = "корок 50 мкм завширшки" },
            .short = .{
                .en = "A pit packed with Helicobacter, stuck to the cells of its wall. The gel over it is neutral: that is their ammonia.",
                .uk = "Ямка, набита гелікобактером, що прилип до клітин її стінки. Гель над нею нейтральний: це їхній аміак.",
            },
            .deep = .{
                .en = "Most of them swim free in the gel; a fifth or so attach to the surface cells and feed on what leaks from them. A colony in a pit sheds swimmers and keeps the edge of the ulcer inflamed, so new epithelium cannot grow in across the crater. Break the colony up: rounds from the mouth of the pit, or the drill. Miss, and you hit the neck of the pit.",
                .uk = "Більшість із них вільно плаває в гелі; приблизно п’ята частина прикріплюється до поверхневих клітин і живиться тим, що з них просочується. Колонія в ямці розсилає плавців і підтримує запалення на краю виразки, тому новий епітелій не може наповзти на кратер. Розбийте колонію: зарядами з устя ямки або свердлом. Схибите — влучите в шийку ямки.",
            },
            .hostile = true,
        },
        .ulcer_margin => .{
            .name = .{ .en = "Ulcer margin", .uk = "Край виразки" },
            .size = .{ .en = "rim 0.1 mm high", .uk = "вал 0,1 мм заввишки" },
            .short = .{
                .en = "The margin of the ulcer. Swollen, inflamed mucosa heaped up around the hole, with no pits in its last third of a millimetre.",
                .uk = "Край виразки. Набрякла, запалена слизова валом довкола отвору; на останній третині міліметра перед ним ямок немає.",
            },
            .deep = .{
                .en = "Healing starts here. Cells at the edge flatten and crawl out over the bed, then pits and glands re-form behind them. That is why the band next to the rim is smooth: it is new epithelium that has not yet folded into pits. It makes little mucus, so the gel thins to nothing before the rim. An edge that stays inflamed never closes.",
                .uk = "Загоєння починається звідси. Клітини на краю сплощуються й наповзають на дно, а вже за ними заново формуються ямки й залози. Тому смуга біля валу гладенька: це новий епітелій, який ще не зібрався в ямки. Слизу він виробляє мало, тож гель сходить нанівець ще до валу. Край, що лишається запаленим, не закриється ніколи.",
            },
        },
        .ulcer_bed => .{
            .name = .{ .en = "Ulcer bed", .uk = "Дно виразки" },
            .size = .{ .en = "0.5 mm below the surface", .uk = "на 0,5 мм нижче від поверхні" },
            .short = .{
                .en = "The bed of the ulcer. Through the mucosa and into the layer under it; what you see is fibrin, dead tissue and new capillaries.",
                .uk = "Дно виразки. Крізь слизову і в шар під нею; те, що ви бачите, — фібрин, мертва тканина й нові капіляри.",
            },
            .deep = .{
                .en = "An erosion stops within the mucosa. An ulcer goes through the muscularis mucosae into the submucosa, where the larger vessels run, and that is why ulcers bleed. The grey-white coat is fibrin and dead cells; under it is granulation tissue, capillary loops and fibroblasts building a scar from the bottom up. No gel covers any of it, so the juice here is at full strength.",
                .uk = "Ерозія зупиняється в межах слизової. Виразка проходить крізь м’язову пластинку слизової в підслизовий шар, де йдуть більші судини, — тому виразки й кровлять. Сіро-білий наліт — це фібрин і мертві клітини; під ним грануляційна тканина: петлі капілярів і фібробласти, що будують рубець знизу вгору. Гелю тут немає зовсім, тож сік діє на повну силу.",
            },
        },
        .bleeding_vessel => .{
            .name = .{ .en = "Eroded arteriole", .uk = "Роз’їдена артеріола" },
            .size = .{ .en = "60 µm across", .uk = "60 мкм завширшки" },
            .short = .{
                .en = "An arteriole the acid has eaten into. It bleeds in pulses, and the blood around it is neutral.",
                .uk = "Артеріола, яку роз’їла кислота. Вона кровить поштовхами, а кров довкола неї нейтральна.",
            },
            .deep = .{
                .en = "The acid dissolved one side of the vessel wall, and acid also keeps a clot from holding: below pH 6 platelets stop sticking and pepsin digests fibrin. Endoscopists close a vessel like this by coaptive coagulation: press the probe on hard enough to flatten the vessel, then heat, so the two walls weld to each other. Heat without pressure fails because flowing blood carries it away. The vessels that put people in hospital are ten times this size.",
                .uk = "Кислота розчинила один бік стінки судини, і вона ж не дає втриматися згустку: при pH, нижчому за 6, тромбоцити перестають злипатися, а пепсин перетравлює фібрин. Ендоскопісти закривають таку судину коаптаційною коагуляцією: притискають зонд так сильно, щоб сплющити судину, а тоді нагрівають — і дві стінки зварюються між собою. Нагрів без притискання не діє, бо кров, що тече, забирає тепло. Судини, з якими потрапляють до лікарні, удесятеро більші за цю.",
            },
        },
        .food_particle => .{
            .name = .{ .en = "Food particle", .uk = "Частинка їжі" },
            .size = .{ .en = "20–50 µm", .uk = "20–50 мкм" },
            .short = .{
                .en = "A particle of her last meal, ground small enough to leave.",
                .uk = "Частинка її останньої їжі, перетерта достатньо дрібно, щоб вийти.",
            },
            .deep = .{
                .en = "The pylorus passes liquid freely and holds solids back until the antrum has ground them to under a millimetre or two. This one is a hundredth of that: a starch grain or a shred of plant cell wall, already on its way. Between meals a different, stronger wave sweeps out whatever would not grind.",
                .uk = "Воротар вільно пропускає рідину, а тверде затримує, доки антральний відділ не перетре його до частинок, менших за міліметр-два. Ця — у сто разів дрібніша: крохмальне зерно або шматочок стінки рослинної клітини, що вже прямує до виходу. Між прийомами їжі інша, сильніша хвиля вимітає все, що перетерти не вдалося.",
            },
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
