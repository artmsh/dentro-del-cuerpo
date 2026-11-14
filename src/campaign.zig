//! Campaign table shown on the route map. Mirrors docs/DESIGN.md.

const Text = @import("i18n.zig").Text;

pub const Chapter = struct {
    name: Text,
    site: Text,
    /// How the drone gets here from the previous chapter.
    route: Text,
    read: Text,
    objective: Text,
    challenge: Text,
    upgrade: Text,
    /// Node position on the body diagram, 0..1 across and down (patient's right is on the left).
    x: f32,
    y: f32,
    hidden: bool = false,
    playable: bool = false,
};

pub const chapters = [_]Chapter{
    .{
        .name = .{ .en = "Vein", .uk = "Вена" },
        .site = .{ .en = "Right great saphenous vein", .uk = "Права велика підшкірна вена" },
        .route = .{ .en = "22 G cannula into the vein at the distal thigh.", .uk = "Канюля 22 G у вену в нижній третині стегна." },
        .read = .{
            .en = "Venous valves: the sinus bulge announces one, the cusps show which way blood is moving, the pocket behind a cusp is stagnant.",
            .uk = "Венозні клапани: випин синуса видає клапан здалеку, стулки показують, куди рухається кров, а в кишені за стулкою кров застоюється.",
        },
        .objective = .{
            .en = "Free a cusp pinned by a septic microthrombus: kill the colonies, cut the fibrin cables, dissolve what comes loose.",
            .uk = "Звільнити стулку, затиснуту септичним мікротромбом: знищити колонії, перерізати фібринові тяжі, розчинити все, що відірветься.",
        },
        .challenge = .{
            .en = "Parabolic flow and calf-pump surges; holding station while both arms work.",
            .uk = "Параболічний профіль течії та поштовхи литкової помпи; утримання позиції, поки працюють обидві руки.",
        },
        .upgrade = .{
            .en = "Sync Servo — both arms on one beat land as one blow.",
            .uk = "Синхросерво — обидві руки в одному такті б’ють як одна.",
        },
        .x = 0.415,
        .y = 0.70,
        .playable = true,
    },
    .{
        .name = .{ .en = "Intestines", .uk = "Кишківник" },
        .site = .{ .en = "Proximal jejunum", .uk = "Проксимальний відділ порожньої кишки" },
        .route = .{
            .en = "Femoral vein → vena cava → right heart → lungs → left heart → aorta → superior mesenteric artery → villus capillary; diapedesis, then out through the villus tip.",
            .uk = "Стегнова вена → порожниста вена → праві відділи серця → легені → ліві відділи серця → аорта → верхня брижова артерія → капіляр ворсинки; діапедез, далі назовні крізь верхівку ворсинки.",
        },
        .read = .{
            .en = "Villi and crypts; the contraction ring of a peristaltic wave and the direction it travels.",
            .uk = "Ворсинки і крипти; кільце скорочення перистальтичної хвилі й напрямок, у якому воно рухається.",
        },
        .objective = .{
            .en = "Clear rotavirus-infected villus tips while sparing healthy enterocytes and the commensal bacteria.",
            .uk = "Очистити верхівки ворсинок, заражені ротавірусом, не зачепивши здорових ентероцитів і коменсальних бактерій.",
        },
        .challenge = .{
            .en = "The lumen closes behind every wave; friend and foe only resolve on a scan.",
            .uk = "Просвіт змикається за кожною хвилею; своїх і чужих можна розрізнити лише скануванням.",
        },
        .upgrade = .{
            .en = "Mucus Tether — anchor to a surface and crawl against the flow.",
            .uk = "Муциновий трос — закріпитися на поверхні й повзти проти течії.",
        },
        .playable = true,
        .x = 0.50,
        .y = 0.515,
    },
    .{
        .name = .{ .en = "Stomach", .uk = "Шлунок" },
        .site = .{ .en = "Gastric antrum", .uk = "Антральний відділ шлунка" },
        .route = .{
            .en = "Up the lumen on the tether: jejunum → duodenum → through the pylorus on a reflux wave.",
            .uk = "Вгору просвітом на тросі: порожня кишка → дванадцятипала кишка → крізь воротар на хвилі рефлюксу.",
        },
        .read = .{
            .en = "Gastric pits and the mucus pH gradient: neutral at the epithelium, pH 2 in the lumen.",
            .uk = "Шлункові ямки та градієнт pH у слизу: нейтральний біля епітелію, pH 2 у просвіті.",
        },
        .objective = .{
            .en = "Clear Helicobacter pylori from an ulcer margin and cauterise the bleeding vessel.",
            .uk = "Очистити край виразки від Helicobacter pylori та припекти судину, що кровить.",
        },
        .challenge = .{
            .en = "Acid erodes the hull outside the mucus; antral grinding waves.",
            .uk = "Поза слизом кислота роз’їдає корпус; перетиральні хвилі антрального відділу.",
        },
        .upgrade = .{
            .en = "Buffer Coat — timed acid immunity; drill cautery.",
            .uk = "Буферне покриття — тимчасова стійкість до кислоти; припікання свердлом.",
        },
        .playable = true,
        .x = 0.545,
        .y = 0.425,
    },
    .{
        .name = .{ .en = "Kidneys", .uk = "Нирки" },
        .site = .{ .en = "Right kidney, lower pole calyx", .uk = "Права нирка, чашечка нижнього полюса" },
        .route = .{
            .en = "Ulcer venule → portal vein → liver → heart → lungs → aorta → renal artery → vasa recta; across a collecting duct to the papilla.",
            .uk = "Венула виразки → ворітна вена → печінка → серце → легені → аорта → ниркова артерія → прямі судини; крізь збірну трубочку до сосочка.",
        },
        .read = .{
            .en = "The pyramid and its papilla; the glomerulus as a filter the drone cannot pass.",
            .uk = "Піраміда та її сосочок; клубочок як фільтр, якого дрон не пройде.",
        },
        .objective = .{
            .en = "Break a calcium-oxalate stone off its Randall's plaque into fragments the ureter will pass.",
            .uk = "Відламати оксалатно-кальцієвий камінь від бляшки Рендалла й подрібнити на уламки, які пропустить сечовід.",
        },
        .challenge = .{
            .en = "Razor crystal shards, urine jets, and fragment-size discipline.",
            .uk = "Гострі як бритва уламки кристалів, струмені сечі та контроль розміру уламків.",
        },
        .upgrade = .{
            .en = "Resonance — a Sync punch becomes a ranged shockwave.",
            .uk = "Резонанс — синхроудар стає ударною хвилею, що б’є на відстані.",
        },
        .x = 0.435,
        .y = 0.455,
    },
    .{
        .name = .{ .en = "Gallbladder", .uk = "Жовчний міхур" },
        .site = .{ .en = "Hartmann's pouch", .uk = "Кишеня Гартмана" },
        .route = .{
            .en = "Renal vein → heart → lungs → aorta → coeliac trunk → cystic artery → wall capillaries → bile.",
            .uk = "Ниркова вена → серце → легені → аорта → черевний стовбур → міхурова артерія → капіляри стінки → жовч.",
        },
        .read = .{
            .en = "Bile layering, mucosal folds, the spiral valve at the neck.",
            .uk = "Шари жовчі, складки слизової, спіральна складка в шийці.",
        },
        .objective = .{
            .en = "Free a cholesterol stone impacted in the neck. Punch and drill fail on wax; bile salts do not.",
            .uk = "Звільнити холестериновий камінь, що застряг у шийці. Удар і свердло безсилі проти воску; жовчні солі — ні.",
        },
        .challenge = .{
            .en = "Contraction crushes everything toward the neck; viscous bile; near darkness.",
            .uk = "Скорочення жене все до шийки; в’язка жовч; майже цілковита темрява.",
        },
        .upgrade = .{ .en = "Emulsifier rounds — dissolve lipid.", .uk = "Емульгувальні заряди — розчиняють ліпіди." },
        .x = 0.455,
        .y = 0.405,
    },
    .{
        .name = .{ .en = "Liver", .uk = "Печінка" },
        .site = .{ .en = "Right lobe, one lobule", .uk = "Права частка, одна часточка" },
        .route = .{
            .en = "Up the bile ducts to a portal triad, then across into the portal venule and the sinusoids.",
            .uk = "Жовчними протоками вгору до портальної тріади, далі — у ворітну венулу та синусоїди.",
        },
        .read = .{
            .en = "The hexagonal lobule: triads at the corners, central vein in the middle, flow always inward.",
            .uk = "Шестикутна часточка: тріади по кутах, центральна вена посередині, течія завжди до центру.",
        },
        .objective = .{
            .en = "Open sinusoids choked by fat-ballooned hepatocytes; clear a portal-borne abscess.",
            .uk = "Відкрити синусоїди, затиснуті роздутими від жиру гепатоцитами; ліквідувати абсцес, занесений ворітною веною.",
        },
        .challenge = .{
            .en = "A single-file maze; Kupffer cells attack an unmarked drone and help a careful one.",
            .uk = "Лабіринт, де пройти можна лише по одному; клітини Купфера атакують непозначений дрон і допомагають обережному.",
        },
        .upgrade = .{ .en = "Opsonin Tag — mark targets for immune cells.", .uk = "Опсонінова мітка — позначає цілі для імунних клітин." },
        .x = 0.44,
        .y = 0.375,
    },
    .{
        .name = .{ .en = "Lungs", .uk = "Легені" },
        .site = .{ .en = "Right lower lobe", .uk = "Нижня частка правої легені" },
        .route = .{
            .en = "Central vein → hepatic veins → vena cava → right heart → pulmonary arteries.",
            .uk = "Центральна вена → печінкові вени → порожниста вена → праві відділи серця → легеневі артерії.",
        },
        .read = .{
            .en = "The alveolus through one breath: capillary mesh, half-micron barrier, surfactant film.",
            .uk = "Альвеола впродовж одного подиху: капілярна сітка, бар’єр у пів мікрона, плівка сурфактанту.",
        },
        .objective = .{
            .en = "Dissolve the emboli that escaped in the leg, then drain a consolidated alveolus of pneumococci.",
            .uk = "Розчинити емболи, що втекли з ноги, а потім осушити альвеолу, заповнену ексудатом із пневмококами.",
        },
        .challenge = .{
            .en = "Air–liquid interfaces trap the drone; everything expands and collapses with the breath.",
            .uk = "Межа повітря й рідини затримує дрон; усе розширюється і спадається з кожним подихом.",
        },
        .upgrade = .{
            .en = "Surfactant Skin — cross air–liquid interfaces.",
            .uk = "Сурфактантна оболонка — дає змогу перетинати межу повітря й рідини.",
        },
        .x = 0.44,
        .y = 0.295,
    },
    .{
        .name = .{ .en = "Heart", .uk = "Серце" },
        .site = .{ .en = "Mitral valve, then the LAD", .uk = "Мітральний клапан, потім передня міжшлуночкова гілка" },
        .route = .{
            .en = "Pulmonary veins → left atrium → mitral valve → left ventricle → aortic root → left coronary ostium.",
            .uk = "Легеневі вени → ліве передсердя → мітральний клапан → лівий шлуночок → корінь аорти → устя лівої коронарної артерії.",
        },
        .read = .{
            .en = "The cardiac cycle from valve states; the coronaries fill in diastole.",
            .uk = "Серцевий цикл за станом клапанів; коронарні артерії наповнюються в діастолу.",
        },
        .objective = .{
            .en = "Strip an endocarditis vegetation from the mitral leaflet; debulk an atheroma without rupturing its cap.",
            .uk = "Зняти ендокардитну вегетацію зі стулки мітрального клапана; зменшити атерому, не розірвавши її покришки.",
        },
        .challenge = .{
            .en = "Violent pulsatile flow; every window is one beat long.",
            .uk = "Шалена пульсівна течія; кожне вікно триває один удар серця.",
        },
        .upgrade = .{
            .en = "Beat Lock — dash and aim phase-locked to the pulse.",
            .uk = "Захоплення ритму — ривок і прицілювання, синхронізовані з пульсом.",
        },
        .x = 0.525,
        .y = 0.315,
    },
    .{
        .name = .{ .en = "Lymph Nodes", .uk = "Лімфатичні вузли" },
        .site = .{ .en = "Right jugulodigastric node", .uk = "Правий яремно-двочеревцевий вузол" },
        .route = .{
            .en = "Aortic arch → right carotid → nodal arteriole → high endothelial venule; the lymphocyte's own way in.",
            .uk = "Дуга аорти → права сонна артерія → артеріола вузла → венула з високим ендотелієм; тим самим шляхом, яким входить лімфоцит.",
        },
        .read = .{
            .en = "Node architecture: sinus, follicles, paracortex, medulla, and who lives where.",
            .uk = "Будова вузла: синус, фолікули, паракортекс, мозкова речовина — і хто де мешкає.",
        },
        .objective = .{
            .en = "Find infected B cells among healthy lymphocytes and present antigen so the node does the killing.",
            .uk = "Знайти заражені B-лімфоцити серед здорових і презентувати антиген, щоб вузол знищив їх сам.",
        },
        .challenge = .{
            .en = "Crowded tissue where nearly everything is friendly and retaliates if harmed.",
            .uk = "Тісна тканина, де майже всі — свої і на удар відповідають ударом.",
        },
        .upgrade = .{ .en = "Antigen Library — call T-cell support.", .uk = "Бібліотека антигенів — виклик підтримки T-лімфоцитів." },
        .x = 0.468,
        .y = 0.195,
    },
    .{
        .name = .{ .en = "Pharynx", .uk = "Глотка" },
        .site = .{ .en = "Tonsillar crypt to olfactory cleft", .uk = "Від крипти мигдалика до нюхової щілини" },
        .route = .{
            .en = "Back up the afferent lymphatic through its valves → palatine tonsil → crypt → oropharynx.",
            .uk = "Назад приносною лімфатичною судиною крізь її клапани → піднебінний мигдалик → крипта → ротоглотка.",
        },
        .read = .{
            .en = "The mucociliary escalator: metachronal waves point to the throat; the swallow wave.",
            .uk = "Мукоциліарний ескалатор: метахрональні хвилі вказують на горло; хвиля ковтання.",
        },
        .objective = .{
            .en = "Break up a streptococcal biofilm and tonsil stones; climb against the cilia to the roof of the nose.",
            .uk = "Зруйнувати стрептококову біоплівку та камені мигдаликів; піднятися проти війок до склепіння носа.",
        },
        .challenge = .{
            .en = "A swallow sweeps the unanchored drone into the oesophagus.",
            .uk = "Ковток змиває незакріплений дрон у стравохід.",
        },
        .upgrade = .{
            .en = "Sheath Glide — travel the perineural space of the olfactory nerve.",
            .uk = "Ковзання під оболонкою нерва — рух периневральним простором нюхового нерва.",
        },
        .x = 0.50,
        .y = 0.165,
    },
    .{
        .name = .{ .en = "Brain", .uk = "Головний мозок" },
        .site = .{ .en = "Third ventricle", .uk = "Третій шлуночок" },
        .route = .{
            .en = "Olfactory filum → cribriform plate → subarachnoid space → lamina terminalis → third ventricle.",
            .uk = "Нюхова нитка → дірчаста пластинка → субарахноїдальний простір → кінцева пластинка → третій шлуночок.",
        },
        .read = .{
            .en = "CSF pulsation and flow from the choroid plexus through the foramina; the fornix, which must not be touched.",
            .uk = "Пульсація ліквору та його течія від судинного сплетення крізь отвори; склепіння, якого не можна торкатися.",
        },
        .objective = .{
            .en = "The operation: fenestrate, crack the calcified cap, emulsify and drain the colloid cyst, cut its pedicle, ride the restored flow out.",
            .uk = "Операція: фенеструвати, розколоти звапнілу покришку, емульгувати й дренувати колоїдну кісту, перерізати її ніжку й вийти з відновленою течією.",
        },
        .challenge = .{
            .en = "Millimetre margins beside structures that hold memory. Every earlier skill, under tighter tolerances.",
            .uk = "Міліметрові допуски поруч зі структурами, що зберігають пам’ять. Усі попередні навички — за жорсткіших допусків.",
        },
        .upgrade = .{ .en = "—", .uk = "—" },
        .x = 0.50,
        .y = 0.085,
    },
    .{
        .name = .{ .en = "Bone Marrow", .uk = "Кістковий мозок" },
        .site = .{ .en = "Right femur", .uk = "Права стегнова кістка" },
        .route = .{
            .en = "Femoral vein → profunda → nutrient vein of the femur → marrow sinusoids.",
            .uk = "Стегнова вена → глибока вена стегна → живильна вена стегнової кістки → синусоїди кісткового мозку.",
        },
        .read = .{
            .en = "Cell lineages: every blood cell you have met, at every age.",
            .uk = "Клітинні лінії: кожна клітина крові, яку ви зустрічали, — у будь-якому віці.",
        },
        .objective = .{
            .en = "Hidden chapter. Found by identifying the three immature cells adrift in the leg vein.",
            .uk = "Прихований розділ. Відкривається, якщо розпізнати три незрілі клітини, що дрейфують у вені ноги.",
        },
        .challenge = .{
            .en = "Megakaryocytes shedding platelets across the only route through.",
            .uk = "Мегакаріоцити, що відшнуровують тромбоцити впоперек єдиного проходу.",
        },
        .upgrade = .{ .en = "Atlas bonus — scans resolve instantly.", .uk = "Бонус атласу — скани розпізнають миттєво." },
        .x = 0.385,
        .y = 0.63,
        .hidden = true,
    },
    .{
        .name = .{ .en = "Inner Ear", .uk = "Внутрішнє вухо" },
        .site = .{ .en = "Right cochlea", .uk = "Права завитка" },
        .route = .{
            .en = "Pharyngotympanic tube (open only during a swallow) → middle ear → round window → scala tympani.",
            .uk = "Слухова труба (відкрита лише під час ковтка) → середнє вухо → кругле вікно → барабанні сходи.",
        },
        .read = .{
            .en = "The travelling wave on the basilar membrane: pitch is a place.",
            .uk = "Біжуча хвиля на базилярній мембрані: висота тону — це місце.",
        },
        .objective = .{
            .en = "Hidden chapter. Found by waiting at the torus tubarius through one swallow in the pharynx.",
            .uk = "Прихований розділ. Відкривається, якщо перечекати один ковток біля трубного валка в глотці.",
        },
        .challenge = .{ .en = "Sound moves the level.", .uk = "Рівень рухається від звуку." },
        .upgrade = .{ .en = "Pressure sense — feel flow through walls.", .uk = "Чуття тиску — відчувати течію крізь стінки." },
        .x = 0.435,
        .y = 0.10,
        .hidden = true,
    },
};

pub const main_count = 11;

/// The chapters that can be flown: the first ones of the route, in order.
pub const playable_count = blk: {
    var n: usize = 0;
    for (chapters) |c| {
        if (!c.playable) break;
        n += 1;
    }
    break :blk n;
};
