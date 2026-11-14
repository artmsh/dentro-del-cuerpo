//! Every piece of text the player reads, in each language, apart from the two tables that keep theirs
//! beside their data: the atlas in guide.zig and the route map in campaign.zig. English is the source text
//! and Ukrainian sits next to it, so a string cannot be added in one language only: `Text` has no default
//! for either field. `src/l10n.zig` walks everything here in its tests.
//!
//! Conventions for the Ukrainian: Marín addresses the pilot as «ви» (no gendered past tense), and speaks of
//! herself in the feminine; key names stay as printed on the keyboard; decimals take a comma, which the
//! formatter supplies for numbers and literals must write themselves; quotation marks are « », the
//! apostrophe is ’ and the dash is —. Tool names in running text match the HUD panel (УДАР, СВЕРДЛО,
//! ПОСТРІЛ), as the English lines match PUNCH, DRILL, SHOOT.
//!
//! Text with numbers in it uses the placeholders of `i18n.expand`: `{0}` for an argument and
//! `{0|one|few|many}` for a word that agrees with it.
//!
//! Text never spells out a key or a button. It names the action, `{@examine}`, and `bindings.zig` puts in
//! what that action is bound to on the device in the player's hands: T, X or □. Where the two devices need
//! different sentences ("hold W" against "push the left stick forward"), the text carries a second wording
//! in `.pad`; the first may then name keys outright, since only a keyboard player sees it. A test in
//! `l10n.zig` fails on any text a controller player could see that still names a key.

const i18n = @import("i18n.zig");
const T = i18n.Text;

/// Names of the three tools, as the arm panels show them.
pub const tool = struct {
    pub const punch: T = .{ .en = "PUNCH", .uk = "УДАР" };
    pub const drill: T = .{ .en = "DRILL", .uk = "СВЕРДЛО" };
    pub const shoot: T = .{ .en = "SHOOT", .uk = "ПОСТРІЛ" };
};

/// What each action is bound to on the keyboard and mouse, as a prompt names it; `bindings.zig` pairs
/// each with its action. Names of keys stay as they are printed on the keyboard.
pub const keys = struct {
    pub const move: T = .{ .en = "W A S D", .uk = "W A S D" };
    pub const look: T = .{ .en = "Mouse / arrow keys", .uk = "Миша / стрілки" };
    pub const up: T = .{ .en = "Space", .uk = "Пробіл" };
    pub const down: T = .{ .en = "C", .uk = "C" };
    pub const boost: T = .{ .en = "Shift", .uk = "Shift" };
    pub const arm_left: T = .{ .en = "Q", .uk = "Q" };
    pub const arm_right: T = .{ .en = "E", .uk = "E" };
    pub const tool_left: T = .{ .en = "Z", .uk = "Z" };
    pub const tool_right: T = .{ .en = "X", .uk = "X" };
    pub const pick_left: T = .{ .en = "1 2 3", .uk = "1 2 3" };
    pub const pick_right: T = .{ .en = "8 9 0", .uk = "8 9 0" };
    pub const examine: T = .{ .en = "T", .uk = "T" };
    pub const hint: T = .{ .en = "H", .uk = "H" };
    pub const tether: T = .{ .en = "G", .uk = "G" };
    pub const skip: T = .{ .en = "Tab", .uk = "Tab" };
    pub const pause: T = .{ .en = "Esc", .uk = "Esc" };
    pub const confirm: T = .{ .en = "Enter", .uk = "Enter" };
    pub const back: T = .{ .en = "Esc", .uk = "Esc" };
    pub const nav: T = .{ .en = "↑ ↓", .uk = "↑ ↓" };
    pub const map: T = .{ .en = "M", .uk = "M" };
    pub const language: T = .{ .en = "Tab", .uk = "Tab" };
    pub const retry: T = .{ .en = "R", .uk = "R" };
    pub const restart: T = .{ .en = "N", .uk = "N" };
    pub const leave: T = .{ .en = "L", .uk = "L" };
    // Quit and full screen are the window's own shortcuts, which differ between systems (Cmd+Q, Alt+F4).
    // They are not written here: the platform layer names them and `bindings.WindowKeys` carries them.
};

/// Names of a game controller's parts, as a prompt names them. The buttons are named as each family prints
/// or documents them: letters on Xbox, shapes on PlayStation. The two buttons beside the Xbox guide button
/// carry only pictograms and take Microsoft's names for them, translated; PlayStation's Create and Options
/// are product names and stay as they are.
pub const pad = struct {
    pub const left_stick: T = .{ .en = "Left stick", .uk = "Лівий стік" };
    pub const right_stick: T = .{ .en = "Right stick", .uk = "Правий стік" };
    pub const dpad_up: T = .{ .en = "D-pad ↑", .uk = "↑ хрестовини" };
    pub const dpad_down: T = .{ .en = "D-pad ↓", .uk = "↓ хрестовини" };
    pub const dpad_left: T = .{ .en = "D-pad ←", .uk = "← хрестовини" };
    pub const dpad_right: T = .{ .en = "D-pad →", .uk = "→ хрестовини" };
    pub const dpad_vertical: T = .{ .en = "D-pad ↑ ↓", .uk = "↑ ↓ хрестовини" };

    pub const xbox = struct {
        pub const a: T = .{ .en = "A", .uk = "A" };
        pub const b: T = .{ .en = "B", .uk = "B" };
        pub const x: T = .{ .en = "X", .uk = "X" };
        pub const y: T = .{ .en = "Y", .uk = "Y" };
        pub const lb: T = .{ .en = "LB", .uk = "LB" };
        pub const rb: T = .{ .en = "RB", .uk = "RB" };
        pub const lt: T = .{ .en = "LT", .uk = "LT" };
        pub const rt: T = .{ .en = "RT", .uk = "RT" };
        pub const ls: T = .{ .en = "LS", .uk = "LS" };
        pub const rs: T = .{ .en = "RS", .uk = "RS" };
        pub const view: T = .{ .en = "View", .uk = "Перегляд" };
        pub const menu: T = .{ .en = "Menu", .uk = "Меню" };
    };

    pub const playstation = struct {
        pub const cross: T = .{ .en = "✕", .uk = "✕" };
        pub const circle: T = .{ .en = "○", .uk = "○" };
        pub const square: T = .{ .en = "□", .uk = "□" };
        pub const triangle: T = .{ .en = "△", .uk = "△" };
        pub const l1: T = .{ .en = "L1", .uk = "L1" };
        pub const r1: T = .{ .en = "R1", .uk = "R1" };
        pub const l2: T = .{ .en = "L2", .uk = "L2" };
        pub const r2: T = .{ .en = "R2", .uk = "R2" };
        pub const l3: T = .{ .en = "L3", .uk = "L3" };
        pub const r3: T = .{ .en = "R3", .uk = "R3" };
        pub const create: T = .{ .en = "Create", .uk = "Create" };
        pub const options: T = .{ .en = "Options", .uk = "Options" };
    };
};

pub const hud = struct {
    pub const sync: T = .{ .en = "SYNC", .uk = "СИНХРО" };
    pub const tissue_damage: T = .{ .en = "TISSUE DAMAGE", .uk = "УШКОДЖЕННЯ ТКАНИНИ" };
    pub const unidentified: T = .{ .en = "UNIDENTIFIED  —  {@examine}", .uk = "НЕ РОЗПІЗНАНО  —  {@examine}" };
    /// Distance, then the entry's size.
    pub const focus: T = .{ .en = "{0}  ·  {1}", .uk = "{0}  ·  {1}" };
    pub const focus_more: T = .{ .en = "{0}  ·  {1}  ·  {@examine}: more", .uk = "{0}  ·  {1}  ·  {@examine}: докладніше" };
    pub const embolus: T = .{ .en = "EMBOLUS", .uk = "ЕМБОЛ" };
    pub const micrometres: T = .{ .en = "{0} µm", .uk = "{0} мкм" };
    pub const millimetres: T = .{ .en = "{0} mm", .uk = "{0} мм" };

    pub const patient: T = .{ .en = "PATIENT", .uk = "ПАЦІЄНТКА" };
    pub const stability: T = .{ .en = "STABILITY", .uk = "СТАБІЛЬНІСТЬ" };
    pub const heart_rate: T = .{ .en = "HR", .uk = "ЧСС" };
    pub const hull: T = .{ .en = "HULL", .uk = "КОРПУС" };
    pub const atlas: T = .{ .en = "ATLAS {0}/{1}", .uk = "АТЛАС {0}/{1}" };
    pub const sync_servo: T = .{ .en = "SYNC SERVO", .uk = "СИНХРОСЕРВО" };

    pub const site_vein: T = .{ .en = "R. GREAT SAPHENOUS VEIN", .uk = "ПРАВА ВЕЛИКА ПІДШКІРНА ВЕНА" };
    pub const site_jejunum: T = .{ .en = "PROXIMAL JEJUNUM", .uk = "ПРОКСИМАЛЬНА ПОРОЖНЯ КИШКА" };
    pub const centimetres: T = .{ .en = "{0} cm", .uk = "{0} см" };
    pub const to_femoral_junction: T = .{ .en = "TO FEMORAL JUNCTION", .uk = "ДО СТЕГНОВОЇ ВЕНИ" };
    pub const past_duodenal_flexure: T = .{ .en = "PAST DUODENAL FLEXURE", .uk = "ВІД ДУОДЕНОЄЮНАЛЬНОГО ВИГИНУ" };
    pub const flow_unit: T = .{ .en = "FLOW  µm/s at 1:100", .uk = "ПОТІК  мкм/с у масштабі 1:100" };
    pub const stream_unit: T = .{ .en = "STREAM  µm/s at 1:100", .uk = "ТЕЧІЯ  мкм/с у масштабі 1:100" };
    pub const contraction_overhead: T = .{ .en = "CONTRACTION — STAY BETWEEN THE VILLI", .uk = "СКОРОЧЕННЯ — ЗАЛИШАЙТЕСЯ МІЖ ВОРСИНКАМИ" };
    pub const contraction_in: T = .{ .en = "CONTRACTION RING IN {0} s", .uk = "КІЛЬЦЕ СКОРОЧЕННЯ ЧЕРЕЗ {0} с" };
    pub const ring_passed: T = .{ .en = "RING PASSED", .uk = "КІЛЬЦЕ ПРОЙШЛО" };
    pub const tethered: T = .{ .en = "TETHERED  ·  {@tether} releases", .uk = "НА ТРОСІ  ·  {@tether} — відпустити" };
    pub const lumen_open: T = .{ .en = "LUMEN OPEN", .uk = "ПРОСВІТ ВІДКРИТИЙ" };
    pub const no_flow: T = .{ .en = "NO FLOW — VEIN OBSTRUCTED", .uk = "ПОТОКУ НЕМАЄ — ВЕНУ ПЕРЕКРИТО" };
    pub const reflux: T = .{ .en = "REFLUX — VALVES SHUT", .uk = "РЕФЛЮКС — КЛАПАНИ ЗАКРИТІ" };
    pub const valves_closing: T = .{ .en = "VALVES CLOSING IN {0} s", .uk = "КЛАПАНИ ЗАКРИЮТЬСЯ ЧЕРЕЗ {0} с" };
    pub const valves_open: T = .{ .en = "VALVES OPEN  ·  {0} s", .uk = "КЛАПАНИ ВІДКРИТІ  ·  {0} с" };

    pub const site_antrum: T = .{ .en = "GASTRIC ANTRUM", .uk = "АНТРАЛЬНИЙ ВІДДІЛ ШЛУНКА" };
    pub const to_pylorus: T = .{ .en = "TO PYLORUS", .uk = "ДО ВОРОТАРЯ" };
    pub const ph_at_hull: T = .{ .en = "pH AT THE HULL", .uk = "pH БІЛЯ КОРПУСУ" };
    pub const wave_overhead: T = .{ .en = "WALLS CLOSED — STAY IN A PIT", .uk = "СТІНКИ ЗІМКНУЛИСЯ — ЗАЛИШАЙТЕСЯ В ЯМЦІ" };
    pub const wave_in: T = .{ .en = "ANTRAL WAVE IN {0} s", .uk = "АНТРАЛЬНА ХВИЛЯ ЧЕРЕЗ {0} с" };
    pub const wave_passed: T = .{ .en = "WAVE PASSED", .uk = "ХВИЛЯ ПРОЙШЛА" };
    pub const acid_on_hull: T = .{ .en = "ACID — HULL ERODING", .uk = "КИСЛОТА — КОРПУС РУЙНУЄТЬСЯ" };
    pub const buffer_coat: T = .{ .en = "BUFFER COAT", .uk = "БУФЕРНЕ ПОКРИТТЯ" };
    pub const coat_holding: T = .{ .en = "ACID — COAT HOLDING  ·  {0} s", .uk = "КИСЛОТА — ПОКРИТТЯ ТРИМАЄ  ·  {0} с" };

    pub const checkpoint_saved: T = .{ .en = "CHECKPOINT SAVED", .uk = "КОНТРОЛЬНУ ТОЧКУ ЗБЕРЕЖЕНО" };
    pub const hidden_route: T = .{ .en = "HIDDEN ROUTE LOGGED: BONE MARROW", .uk = "ЗАПИСАНО ПРИХОВАНИЙ МАРШРУТ: КІСТКОВИЙ МОЗОК" };

    pub const left_arm: T = .{
        .en = "LEFT ARM  ·  {@arm_left}  /  left click",
        .uk = "ЛІВА РУКА  ·  {@arm_left}  /  ліва кнопка миші",
        .pad = &.{ .en = "LEFT ARM  ·  {@arm_left}", .uk = "ЛІВА РУКА  ·  {@arm_left}" },
    };
    pub const right_arm: T = .{
        .en = "RIGHT ARM  ·  {@arm_right}  /  right click",
        .uk = "ПРАВА РУКА  ·  {@arm_right}  /  права кнопка миші",
        .pad = &.{ .en = "RIGHT ARM  ·  {@arm_right}", .uk = "ПРАВА РУКА  ·  {@arm_right}" },
    };
    pub const charge: T = .{ .en = "CHARGE", .uk = "ЗАРЯД" };
    pub const overheated: T = .{ .en = "OVERHEATED", .uk = "ПЕРЕГРІВ" };
    pub const cutting: T = .{ .en = "CUTTING", .uk = "РІЖЕ" };
    pub const heat: T = .{ .en = "HEAT", .uk = "НАГРІВ" };
    pub const ready: T = .{ .en = "READY", .uk = "ГОТОВО" };
    pub const left_keys: T = .{
        .en = "{@tool_left}: change tool   {@pick_left}: punch / drill / shoot",
        .uk = "{@tool_left}: змінити   {@pick_left}: удар / свердло / постріл",
        .pad = &.{ .en = "{@tool_left}: next tool   {@pick_left}: previous", .uk = "{@tool_left}: наступний   {@pick_left}: попередній" },
    };
    pub const right_keys: T = .{
        .en = "{@tool_right}: change tool   {@pick_right}: punch / drill / shoot",
        .uk = "{@tool_right}: змінити   {@pick_right}: удар / свердло / постріл",
        .pad = &.{ .en = "{@tool_right}: next tool   {@pick_right}: previous", .uk = "{@tool_right}: наступний   {@pick_right}: попередній" },
    };

    /// The speaker label over a comms line.
    pub const marin: T = .{ .en = "DRA. MARÍN", .uk = "Д-Р МАРІН" };

    pub const arrival_chapter: T = .{ .en = "CHAPTER 2  ·  TRANSIT COMPLETE", .uk = "РОЗДІЛ 2  ·  ТРАНЗИТ ЗАВЕРШЕНО" };
    pub const arrival_place: T = .{ .en = "Proximal jejunum", .uk = "Проксимальна порожня кишка" };
    pub const arrival_route = [2]T{
        .{ .en = "femoral vein → vena cava → right heart → lungs → left heart → aorta →", .uk = "стегнова вена → порожниста вена → праве серце → легені → ліве серце → аорта →" },
        .{ .en = "superior mesenteric artery → villus capillary → out through the tip", .uk = "верхня брижова артерія → капіляр ворсинки → назовні крізь верхівку" },
    };
    pub const arrival3_chapter: T = .{ .en = "CHAPTER 3  ·  TRANSIT COMPLETE", .uk = "РОЗДІЛ 3  ·  ТРАНЗИТ ЗАВЕРШЕНО" };
    pub const arrival3_place: T = .{ .en = "Gastric antrum", .uk = "Антральний відділ шлунка" };
    pub const arrival3_route = [2]T{
        .{ .en = "jejunal lumen, against the stream on the tether → duodenum →", .uk = "просвіт порожньої кишки, проти течії на тросі → дванадцятипала кишка →" },
        .{ .en = "pylorus, on a wave of duodenogastric reflux → mucus gel of the antrum", .uk = "воротар, на хвилі дуоденогастрального рефлюксу → слизовий гель антрального відділу" },
    };
    pub const transit: T = .{ .en = "TRANSIT — TEMPO LINK 1:1", .uk = "ТРАНЗИТ — МАСШТАБ ЧАСУ 1:1" };
    pub const transit_distance: T = .{ .en = "{0} cm to femoral junction", .uk = "{0} см до стегнової вени" };

    pub const controls: T = .{
        .en = "WASD move   Space / C up, down   Shift boost   T identify   H hint   Tab skip line   Esc pause",
        .uk = "WASD рух   Пробіл / C вгору, вниз   Shift прискорення   T розпізнати   H підказка   Tab пропустити репліку   Esc пауза",
        .pad = &.{
            .en = "{@move}: move   {@up} / {@down}: up, down   {@boost}: boost   {@examine}: identify   {@hint}: hint   {@skip}: skip line   {@pause}: pause",
            .uk = "{@move}: рух   {@up} / {@down}: вгору, вниз   {@boost}: прискорення   {@examine}: розпізнати   {@hint}: підказка   {@skip}: пропустити репліку   {@pause}: пауза",
        },
    };
    pub const controls_tether: T = .{
        .en = "WASD move   Space / C up, down   Shift boost   G tether   T scan   H hint   Tab skip   Esc pause",
        .uk = "WASD рух   Пробіл / C вгору, вниз   Shift прискорення   G трос   T скан   H підказка   Tab пропустити   Esc пауза",
        .pad = &.{
            .en = "{@move}: move   {@up} / {@down}: up, down   {@boost}: boost   {@tether}: tether   {@examine}: scan   {@hint}: hint   {@skip}: skip   {@pause}: pause",
            .uk = "{@move}: рух   {@up} / {@down}: вгору, вниз   {@boost}: прискорення   {@tether}: трос   {@examine}: скан   {@hint}: підказка   {@skip}: пропустити   {@pause}: пауза",
        },
    };
    /// The strip for chapters that carry the tether and identify with a look rather than a scan pulse.
    pub const controls_tether_identify: T = .{
        .en = "WASD move   Space / C up, down   Shift boost   G tether   T identify   H hint   Tab skip   Esc pause",
        .uk = "WASD рух   Пробіл / C вгору, вниз   Shift прискорення   G трос   T розпізнати   H підказка   Tab пропустити   Esc пауза",
        .pad = &.{
            .en = "{@move}: move   {@up} / {@down}: up, down   {@boost}: boost   {@tether}: tether   {@examine}: identify   {@hint}: hint   {@skip}: skip   {@pause}: pause",
            .uk = "{@move}: рух   {@up} / {@down}: вгору, вниз   {@boost}: прискорення   {@tether}: трос   {@examine}: розпізнати   {@hint}: підказка   {@skip}: пропустити   {@pause}: пауза",
        },
    };
};

/// The cards that stop play: upgrades, the two failures, and the debrief.
pub const card = struct {
    pub const tether_kicker: T = .{ .en = "MUCIN SYNTHESIS CALIBRATED  —  UPGRADE", .uk = "СИНТЕЗ МУЦИНУ ВІДКАЛІБРОВАНО  —  ПОКРАЩЕННЯ" };
    pub const tether_name: T = .{ .en = "MUCUS TETHER", .uk = "МУЦИНОВИЙ ТРОС" };
    pub const tether_body: T = .{
        .en = "{@tether} fires a mucin line at whatever tissue the reticle is on, up to 0.4 mm away, reels the drone in and holds it there against any stream. {@tether} on a new point moves the line; {@tether} on nothing releases it. Hold on through a contraction, or cross a stream the thrusters cannot beat one pull at a time.",
        .uk = "{@tether} вистрілює муциновий трос у тканину під прицілом на відстань до 0,4 мм, підтягує дрон і втримує його там проти будь-якої течії. {@tether} на новій точці переносить трос; {@tether} у порожнечу відпускає його. Перечекайте на ньому скорочення або здолайте течію, непосильну для двигунів, — ривок за ривком.",
    };
    pub const sync_kicker: T = .{ .en = "FIELD CALIBRATION COMPLETE  —  UPGRADE", .uk = "ПОЛЬОВЕ КАЛІБРУВАННЯ ЗАВЕРШЕНО  —  ПОКРАЩЕННЯ" };
    pub const sync_name: T = .{ .en = "SYNC SERVO", .uk = "СИНХРОСЕРВО" };
    pub const sync_body: T = .{
        .en = "Trigger both arms within a tenth of a second and they land as one Sync Strike. Two punches hit ten times as hard as one, enough to shatter calcium, with a shockwave that clears small organisms around you. Two rounds merge into a lance that pierces and does the damage of three.",
        .uk = "Запустіть обидві руки з різницею до десятої частки секунди — і вони спрацюють як один синхроудар. Два удари б’ють удесятеро сильніше за один — досить, щоб розбити кальцій, — і здіймають ударну хвилю, що змітає дрібні організми довкола. Два заряди зливаються у спис, що пробиває наскрізь і завдає шкоди, як три заряди.",
    };
    pub const coat_kicker: T = .{ .en = "BUFFER RESERVOIR CHARGED  —  UPGRADE", .uk = "БУФЕРНИЙ РЕЗЕРВУАР ЗАРЯДЖЕНО  —  ПОКРАЩЕННЯ" };
    pub const coat_name: T = .{ .en = "BUFFER COAT  +  CAUTERY BIT", .uk = "БУФЕРНЕ ПОКРИТТЯ  +  КОАГУЛЯЦІЙНЕ СВЕРДЛО" };
    pub const coat_body: T = .{
        .en = "The hull now carries a bicarbonate reserve. In acid it spends itself instead of the hull: twelve seconds, shown under the hull bar, refilled in neutral gel or in blood. There is nothing to press; it works when acid touches you. The drill bit now heats as it turns. Held on a vessel that the other arm is pressing flat with PUNCH, it welds the walls together.",
        .uk = "Корпус тепер несе запас бікарбонату. У кислоті витрачається він, а не корпус: дванадцять секунд — шкала під смугою корпусу; запас поповнюється в нейтральному гелі або в крові. Натискати нічого не треба: покриття спрацьовує, щойно вас торкнеться кислота. А свердло тепер нагрівається під час обертання. Якщо тримати його на судині, яку друга рука сплющує УДАРОМ, воно зварює її стінки.",
    };
    pub const install: T = .{ .en = "{@confirm} — install", .uk = "{@confirm} — встановити" };

    pub const signal_lost: T = .{ .en = "SIGNAL LOST", .uk = "СИГНАЛ ВТРАЧЕНО" };
    pub const hull_failed: T = .{ .en = "The hull failed. The patient is unharmed; the drone is not.", .uk = "Корпус не витримав. Пацієнтка не постраждала, а от дрон — так." };
    pub const relaunch: T = .{ .en = "{@confirm} — relaunch from the last checkpoint", .uk = "{@confirm} — перезапуск з останньої контрольної точки" };
    pub const patient_lost: T = .{ .en = "PATIENT LOST", .uk = "ПАЦІЄНТКУ ВТРАЧЕНО" };
    pub const lost_vein: T = .{ .en = "Too much damage to healthy tissue, too many emboli. She did not make it.", .uk = "Забагато ушкоджень здорової тканини, забагато емболів. Вона не вижила." };
    pub const lost_gut: T = .{ .en = "Too much damage to the lining, too much virus spread. She did not make it.", .uk = "Забагато ушкоджень слизової, вірус поширився надто далеко. Вона не вижила." };
    pub const lost_stomach: T = .{ .en = "Too much damage to the lining, too much blood lost. She did not make it.", .uk = "Забагато ушкоджень слизової, забагато втраченої крові. Вона не вижила." };
    pub const restart: T = .{ .en = "{@confirm} — restart the chapter", .uk = "{@confirm} — почати розділ заново" };

    pub const vein_kicker: T = .{ .en = "CHAPTER 1  ·  VEIN", .uk = "РОЗДІЛ 1  ·  ВЕНА" };
    pub const vein_title: T = .{ .en = "Into the femoral vein", .uk = "До стегнової вени" };
    pub const gut_kicker: T = .{ .en = "CHAPTER 2  ·  INTESTINES", .uk = "РОЗДІЛ 2  ·  КИШКІВНИК" };
    pub const gut_title: T = .{ .en = "Up the lumen", .uk = "Вгору просвітом" };

    pub const stomach_kicker: T = .{ .en = "CHAPTER 3  ·  STOMACH", .uk = "РОЗДІЛ 3  ·  ШЛУНОК" };
    pub const stomach_title: T = .{ .en = "Out through the venule", .uk = "Назовні крізь венулу" };
    pub const row_stability: T = .{ .en = "Patient stability", .uk = "Стабільність пацієнтки" };
    pub const row_emboli: T = .{ .en = "Emboli that reached the lungs", .uk = "Емболів, що дісталися легень" };
    pub const row_tissue: T = .{ .en = "Hits on healthy tissue", .uk = "Влучань у здорову тканину" };
    pub const row_friendly_fire: T = .{ .en = "Immune cells lost to friendly fire", .uk = "Імунних клітин, утрачених від вогню по своїх" };
    pub const row_sync: T = .{ .en = "Sync Strikes landed", .uk = "Синхроударів" };
    pub const row_atlas: T = .{ .en = "Atlas entries identified", .uk = "Розпізнано статей атласу" };
    pub const row_relaunches: T = .{ .en = "Relaunches", .uk = "Перезапусків" };
    pub const row_time: T = .{ .en = "Time on the link", .uk = "Час на зв’язку" };
    pub const row_cleared: T = .{ .en = "Infected cells cleared", .uk = "Видалено заражених клітин" };
    pub const row_spread: T = .{ .en = "Times the virus spread", .uk = "Випадків поширення вірусу" };
    pub const row_commensals: T = .{ .en = "Commensal bacteria killed", .uk = "Убито коменсальних бактерій" };
    pub const row_lining: T = .{ .en = "Hits on the lining", .uk = "Влучань у слизову" };
    pub const row_colonies: T = .{ .en = "Colonised pits cleared", .uk = "Очищено колонізованих ямок" };
    pub const row_acid: T = .{ .en = "Seconds of acid on bare hull", .uk = "Секунд у кислоті без покриття" };
    pub const row_crushed: T = .{ .en = "Times caught between the walls", .uk = "Разів затиснуто між стінками" };
    pub const row_bleed: T = .{ .en = "Seconds the vessel bled", .uk = "Секунд, що кровила судина" };
    pub const out_of_100: T = .{ .en = "{0} / 100", .uk = "{0} / 100" };
    pub const out_of: T = .{ .en = "{0} / {1}", .uk = "{0} / {1}" };
    pub const duration: T = .{ .en = "{0} min {1} s", .uk = "{0} хв {1} с" };

    pub const note_no_emboli: T = .{ .en = "No emboli escaped. The lungs will be a shorter job.", .uk = "Жоден ембол не втік. У легенях роботи буде менше." };
    pub const note_emboli: T = .{ .en = "What escaped is lodged in her pulmonary arteries. You will meet it again in chapter 7.", .uk = "Те, що втекло, застрягло в її легеневих артеріях. Ви зустрінетеся з ним знову в розділі 7." };
    pub const note_hidden_route: T = .{ .en = "Hidden route logged: Bone Marrow", .uk = "Записано прихований маршрут: кістковий мозок" };
    pub const note_gut_clean: T = .{ .en = "Nothing spread and her flora is intact. The villi will be back within the week.", .uk = "Вірус не поширився, і її флора ціла. Ворсинки відновляться за тиждень." };
    pub const note_gut_flora: T = .{ .en = "The virus is cleared, and so is some of what kept other things out.", .uk = "Вірус усунено — а разом із ним і частину того, що не пускало сюди інших." };
    pub const note_gut_spread: T = .{ .en = "Cleared. What spread will slow her recovery by a day or two.", .uk = "Усунено. Те, що встигло поширитися, затримає її одужання на день-два." };
    pub const note_stomach_clean: T = .{ .en = "Margin clear and the vessel welded without delay. With the bacteria gone the crater will close in a few weeks.", .uk = "Край чистий, судину заварено без зволікань. Без бактерій кратер закриється за кілька тижнів." };
    pub const note_stomach_bled: T = .{ .en = "The vessel is shut. She lost more blood than she needed to while it was open.", .uk = "Судину закрито. Поки вона була відкрита, пацієнтка втратила більше крові, ніж мусила." };
    pub const note_stomach_lining: T = .{ .en = "The ulcer will heal. The pits you hit will take a few days longer than the rest.", .uk = "Виразка загоїться. Ямкам, у які ви влучили, знадобиться на кілька днів більше, ніж решті." };
    pub const to_route_map: T = .{ .en = "{@confirm} — route map", .uk = "{@confirm} — карта маршруту" };
    /// The caption beside the grade letter on the debrief.
    pub const grade: T = .{ .en = "GRADE", .uk = "ОЦІНКА" };
};

pub const pause = struct {
    pub const heading: T = .{ .en = "PAUSED", .uk = "ПАУЗА" };
    /// What resumes the game, beside the first option. The other options show their own key, if they have one.
    pub const resume_keys: T = .{ .en = "{@back}", .uk = "{@back}", .pad = &.{ .en = "{@back} / {@pause}", .uk = "{@back} / {@pause}" } };
    /// The options, in the order `app.PauseItem` lists them; the language switch follows as one more.
    pub const options = [_]T{
        .{ .en = "Resume", .uk = "Продовжити" },
        .{ .en = "Relaunch from last checkpoint", .uk = "Перезапуск з останньої контрольної точки" },
        .{ .en = "Restart chapter", .uk = "Почати розділ заново" },
        .{ .en = "Leave to title", .uk = "Вийти на титульний екран" },
        .{ .en = "Quit game", .uk = "Вийти з гри" },
    };
    /// How to choose an option without its own key.
    pub const choose: T = .{ .en = "{@nav} select    {@confirm} choose", .uk = "{@nav} вибір    {@confirm} обрати" };
    /// Control, then what it does.
    pub const controls = [_][2]T{
        .{ .{ .en = "{@look}", .uk = "{@look}" }, .{ .en = "Look", .uk = "Огляд" } },
        .{ .{ .en = "{@move}", .uk = "{@move}" }, .{ .en = "Thrust and strafe", .uk = "Тяга і рух убік" } },
        .{ .{ .en = "{@up} / {@down}", .uk = "{@up} / {@down}" }, .{ .en = "Up / down", .uk = "Вгору / вниз" } },
        .{
            .{ .en = "{@boost}", .uk = "{@boost}" },
            .{ .en = "Boost", .uk = "Прискорення", .pad = &.{ .en = "Boost: click once, it lasts while the stick is pushed", .uk = "Прискорення: натисніть раз, діє, поки стік відхилено" } },
        },
        .{
            .{ .en = "{@arm_left}  ·  left click", .uk = "{@arm_left}  ·  ліва кнопка миші", .pad = &.{ .en = "{@arm_left}", .uk = "{@arm_left}" } },
            .{ .en = "Left arm", .uk = "Ліва рука" },
        },
        .{
            .{ .en = "{@arm_right}  ·  right click", .uk = "{@arm_right}  ·  права кнопка миші", .pad = &.{ .en = "{@arm_right}", .uk = "{@arm_right}" } },
            .{ .en = "Right arm", .uk = "Права рука" },
        },
        .{ .{ .en = "{@tool_left} / {@tool_right}", .uk = "{@tool_left} / {@tool_right}" }, .{ .en = "Cycle left / right arm tool", .uk = "Змінити інструмент лівої / правої руки" } },
        .{
            .{ .en = "{@pick_left}  ·  {@pick_right}", .uk = "{@pick_left}  ·  {@pick_right}" },
            .{
                .en = "Punch, drill, shoot on left · right arm",
                .uk = "Удар, свердло, постріл на лівій · правій руці",
                .pad = &.{ .en = "Previous tool on left · right arm", .uk = "Попередній інструмент лівої · правої руки" },
            },
        },
        .{ .{ .en = "{@examine}", .uk = "{@examine}" }, .{ .en = "Identify what the reticle is on (again for more)", .uk = "Розпізнати те, що під прицілом (ще раз — докладніше)" } },
        .{ .{ .en = "{@hint}", .uk = "{@hint}" }, .{ .en = "Hint", .uk = "Підказка" } },
        .{ .{ .en = "{@skip}", .uk = "{@skip}" }, .{ .en = "Skip the current line", .uk = "Пропустити поточну репліку" } },
    };
    /// The chapter 2 upgrade, listed once the drone carries it.
    pub const tether = [2]T{
        .{ .en = "{@tether}", .uk = "{@tether}" },
        .{ .en = "Mucus Tether: attach to tissue, release on nothing", .uk = "Муциновий трос: зачепитися за тканину; у порожнечу — відпустити" },
    };
    /// The chapter 3 upgrade, listed once the drone carries it. It has no control of its own.
    pub const coat = [2]T{
        .{ .en = "auto", .uk = "авто" },
        .{ .en = "Buffer Coat: 12 s in acid; refills in neutral gel or blood", .uk = "Буферне покриття: 12 с у кислоті; поповнюється в нейтральному гелі або крові" },
    };
    /// A control that exists only on the keyboard: the window's own shortcut, which the platform names.
    /// It is listed when the prompts are for the keyboard.
    pub const fullscreen: T = .{ .en = "Full screen", .uk = "На весь екран" };
};

/// The language switch on the title and pause screens: the key, then this label, then each language's own name.
pub const language = struct {
    pub const key: T = .{ .en = "{@language}", .uk = "{@language}" };
    pub const label: T = .{ .en = "Language", .uk = "Мова" };
};

pub const title = struct {
    pub const tagline: T = .{ .en = "I N S I D E   T H E   B O D Y", .uk = "У С Е Р Е Д И Н І   Т І Л А" };
    /// The entries, in the order `app.TitleItem` lists them, apart from the language switch, which is
    /// drawn from `language` below.
    pub const begin: T = .{ .en = "Begin", .uk = "Почати" };
    pub const route_map: T = .{ .en = "Route map", .uk = "Карта маршруту" };
    pub const quit: T = .{ .en = "Quit game", .uk = "Вийти з гри" };
    /// How to choose an entry.
    pub const choose: T = .{ .en = "{@nav} select    {@confirm} choose", .uk = "{@nav} вибір    {@confirm} обрати" };
    pub const progress_one: T = .{ .en = "Chapter 1 complete  ·  grade {0}  ·  chapter 2 is open on the route map — {@map}", .uk = "Розділ 1 завершено  ·  оцінка {0}  ·  розділ 2 відкрито на карті маршруту — {@map}" };
    pub const progress_two: T = .{ .en = "Chapters 1 and 2 complete  ·  grades {0} and {1}  ·  {@map} for the route map", .uk = "Розділи 1 і 2 завершено  ·  оцінки {0} і {1}  ·  {@map} — карта маршруту" };
    /// Three chapters or more: the number of the last one finished, then their grades in order.
    pub const progress_many: T = .{ .en = "Chapters 1–{0} complete  ·  grades {1}  ·  {@map} for the route map", .uk = "Розділи 1–{0} завершено  ·  оцінки {1}  ·  {@map} — карта маршруту" };
    pub const backdrop: T = .{ .en = "Right great saphenous vein, 3.6 mm across. Every disc is a red blood cell, 7.8 µm.", .uk = "Права велика підшкірна вена, 3,6 мм у діаметрі. Кожен диск — еритроцит, 7,8 мкм." };
};

pub const briefing = struct {
    pub const heading: T = .{ .en = "BRIEFING  ·  {0} / {1}", .uk = "ІНСТРУКТАЖ  ·  {0} / {1}" };
    pub const launch: T = .{ .en = "{@confirm} — launch", .uk = "{@confirm} — старт" };
    pub const next: T = .{ .en = "{@confirm} — continue", .uk = "{@confirm} — далі" };
    pub const pages = [_]T{
        .{
            .en = "Patient: 58, colloid cyst of the third ventricle. It plugs the foramina of Monro without warning; the next time may be the last. She is septic from an infected clot in her right leg, and she will not survive open surgery.\n\nSo we go in through the leg.",
            .uk = "Пацієнтка: 58 років, колоїдна кіста третього шлуночка. Кіста без попередження перекриває отвори Монро; наступний раз може стати останнім. У неї сепсис від інфікованого тромбу в правій нозі, і відкритої операції вона не переживе.\n\nТому ми заходимо через ногу.",
        },
        .{
            .en = "You fly a drone the size of a red blood cell: eight micrometres. Two arms, each fitted with a punch, a drill or a lytic emitter, each on its own trigger.\n\nYour display removes ninety-nine red cells in a hundred, or blood would be a wall. Your link runs at one-hundredth speed, so a second of your time is ten milliseconds of hers.",
            .uk = "Ви керуєте дроном завбільшки з еритроцит: вісім мікрометрів. Дві руки, на кожній — ударник, свердло або літичний випромінювач, у кожної свій спуск.\n\nВаш дисплей прибирає дев’яносто дев’ять еритроцитів зі ста, інакше кров була б суцільною стіною. Зв’язок працює в масштабі часу один до ста: секунда вашого часу — це десять мілісекунд її часу.",
        },
        .{
            .en = "Every stop between here and the brain removes something that would kill her before the operation, and teaches the drone something it needs at the end. First stop is the clot.\n\nI'm Elena Marín. I'll be on comms the whole way. Point at anything and press {@examine} — I'll tell you what it is.",
            .uk = "Кожна зупинка на шляху до мозку усуває щось, що вбило б її ще до операції, і вчить дрон чогось, що знадобиться наприкінці. Перша зупинка — тромб.\n\nЯ Елена Марін. Буду на зв’язку всю дорогу. Наведіть приціл на що завгодно й натисніть {@examine} — я скажу, що це.",
        },
    };
};

pub const map = struct {
    pub const heading: T = .{ .en = "Route", .uk = "Маршрут" };
    pub const subtitle: T = .{ .en = "right leg to third ventricle  ·  eleven stops, two off the chart", .uk = "від правої ноги до третього шлуночка  ·  одинадцять зупинок і дві поза картою" };
    pub const unknown_row: T = .{ .en = "— unknown —", .uk = "— невідомо —" };
    pub const complete: T = .{ .en = "complete", .uk = "завершено" };
    pub const playable: T = .{ .en = "playable", .uk = "доступно" };
    pub const locked: T = .{ .en = "locked", .uk = "заблоковано" };
    pub const hidden: T = .{ .en = "hidden", .uk = "приховано" };
    pub const route_logged: T = .{ .en = "route logged", .uk = "маршрут записано" };
    pub const mapped: T = .{ .en = "mapped", .uk = "на карті" };
    pub const unknown_name: T = .{ .en = "Unknown", .uk = "Невідомо" };
    pub const unknown_site: T = .{ .en = "Something along the way does not belong. Look closely.", .uk = "Дорогою трапиться щось, чому там не місце. Придивляйтеся." };
    pub const field_route: T = .{ .en = "HOW THE DRONE GETS THERE", .uk = "ЯК ДРОН ТУДИ ПОТРАПЛЯЄ" };
    pub const field_read: T = .{ .en = "WHAT YOU LEARN TO READ", .uk = "ЩО ВИ ВЧИТЕСЯ ЧИТАТИ" };
    pub const field_objective: T = .{ .en = "OBJECTIVE", .uk = "ЗАВДАННЯ" };
    pub const field_challenge: T = .{ .en = "WHAT MAKES IT HARD HERE", .uk = "У ЧОМУ ТУТ СКЛАДНІСТЬ" };
    pub const field_upgrade: T = .{ .en = "UPGRADE", .uk = "ПОКРАЩЕННЯ" };
    pub const fly: T = .{ .en = "{@confirm} — fly this chapter", .uk = "{@confirm} — летіти сюди" };
    pub const need_previous: T = .{ .en = "Complete the chapter before it to fly this one.", .uk = "Щоб летіти сюди, завершіть попередній розділ." };
    pub const not_found: T = .{ .en = "Not yet found.", .uk = "Ще не знайдено." };
    pub const not_built: T = .{ .en = "Designed and routed; not yet flyable in this build.", .uk = "Спроєктовано й нанесено на карту; у цій збірці ще недоступно." };
    pub const keys: T = .{ .en = "{@nav} select    {@confirm} fly    {@back} back", .uk = "{@nav} вибір    {@confirm} летіти    {@back} назад" };
};

/// The application menu in the menu bar.
pub const menu = struct {
    pub const fullscreen: T = .{ .en = "Toggle Full Screen", .uk = "На весь екран" };
    pub const quit: T = .{ .en = "Quit Dentro del cuerpo", .uk = "Вийти з Dentro del cuerpo" };
};

/// Marín's lines, named by how they begin. Chapter 1, then chapter 2, in the order the script reaches them.
pub const line = struct {
    pub const thats_healthy_tissue: T = .{ .en = "That's healthy tissue. Every hit starts a clot.", .uk = "Це здорова тканина. Кожне влучання запускає згортання." };
    pub const that_cell_was_on_our_side: T = .{ .en = "That cell was on our side. Check before you fire.", .uk = "Ця клітина була на нашому боці. Перевіряйте, перш ніж стріляти." };
    pub const comms_check: T = .{
        .en = "Comms check. Elena Marín — I'm on your shoulder for the whole run.",
        .uk = "Перевірка зв’язку. Елена Марін — я буду у вас за плечем увесь політ.",
    };
    pub const youre_inside_the_cannula: T = .{
        .en = "You're inside the cannula, in a vein of the right thigh. Mouse or arrow keys to look, W to thrust.",
        .uk = "Ви в канюлі, у вені правого стегна. Миша або стрілки — огляд, W — тяга.",
        .pad = &.{
            .en = "You're inside the cannula, in a vein of the right thigh. Right stick to look, left stick to thrust.",
            .uk = "Ви в канюлі, у вені правого стегна. Правий стік — огляд, лівий — тяга.",
        },
    };
    pub const first_lesson: T = .{
        .en = "First lesson, because everything after depends on it: blood in a vessel does not move as one block. Fly out to the wall and stop there.",
        .uk = "Перший урок, бо від нього залежить усе подальше: кров у судині не рухається суцільною масою. Підлетіть до стінки й зупиніться там.",
    };
    pub const feel_it_against_the_wall: T = .{
        .en = "Feel it? Against the wall the blood is almost still. That's where you rest, and where you work.",
        .uk = "Відчуваєте? Біля стінки кров майже стоїть. Тут ви відпочиваєте, і тут працюєте.",
    };
    pub const now_the_middle_of_the_stream: T = .{ .en = "Now the middle of the stream.", .uk = "Тепер — у середину потоку." };
    pub const and_here_it_carries_you: T = .{
        .en = "And here it carries you. Core to travel, wall to hold — flow speed is on your top right.",
        .uk = "А тут вас несе. Серединою — щоб рухатися, біля стінки — щоб триматися на місці. Швидкість потоку — вгорі праворуч.",
    };
    pub const ride_it_downstream: T = .{ .en = "Ride it downstream. Watch for the wall changing shape.", .uk = "Пливіть за течією. Стежте, де стінка змінить форму." };
    pub const there_the_wall_bulges: T = .{
        .en = "There: the wall bulges. Put your reticle on the pale flap inside the bulge and press {@examine}. Ask me about anything that way.",
        .uk = "Ось: стінка випинається. Наведіть приціл на бліду заслінку всередині випину й натисніть {@examine}. Так можна спитати мене про будь-що.",
    };
    pub const watch_one_cycle: T = .{
        .en = "Watch one cycle. When the calf relaxes, blood falls back, the cusps meet and nothing passes. Go through while they lie open.",
        .uk = "Простежте один цикл. Коли литковий м’яз розслабляється, кров падає назад, стулки змикаються і ніщо не проходить. Проходьте, поки вони відкриті.",
    };
    pub const clean_position_saved: T = .{ .en = "Clean. I've saved your position.", .uk = "Чисто. Я зберегла вашу позицію." };
    pub const pale_cells_are_rolling: T = .{
        .en = "Pale cells are rolling along the wall down here. Get your reticle on one and identify it.",
        .uk = "Тут по стінці котяться бліді клітини. Наведіть приціл на одну з них і розпізнайте її.",
    };
    pub const more_of_them_on_the_wall: T = .{
        .en = "More of them on the wall means infection close by. And here is the reason.",
        .uk = "Що більше їх на стінці, то ближче інфекція. А ось і причина.",
    };
    pub const bacteria_ahead: T = .{
        .en = "Bacteria ahead. Left arm is {@arm_left}, right arm is {@arm_right}. Your left arm carries lytic rounds: hold {@arm_left}.",
        .uk = "Попереду бактерії. Ліва рука — {@arm_left}, права — {@arm_right}. У лівій руці літичні заряди: утримуйте {@arm_left}.",
    };
    pub const each_arm_carries_three_tools: T = .{
        .en = "Each arm carries three tools. {@tool_left} cycles the left arm, {@tool_right} the right. Rounds for organisms, the drill for anything fibrous, the punch for anything brittle — and the arms work at the same time.",
        .uk = "На кожній руці три інструменти. {@tool_left} перемикає ліву руку, {@tool_right} — праву. Заряди — для мікроорганізмів, свердло — для всього волокнистого, удар — для всього крихкого. І руки працюють одночасно.",
    };
    pub const fit_the_drill_to_one_arm: T = .{
        .en = "Fit the drill to one arm and keep rounds on the other. You will need both at once.",
        .uk = "Поставте свердло на одну руку, а на другій залиште заряди. Знадобляться обидва водночас.",
    };
    pub const next_valve: T = .{
        .en = "Next valve. Look at the upper cusp: it isn't moving. Something behind it is holding it shut.",
        .uk = "Наступний клапан. Погляньте на верхню стулку: вона не рухається. Щось позаду тримає її закритою.",
    };
    pub const go_past_its_free_edge: T = .{
        .en = "Go past its free edge, then back down into the pocket behind it.",
        .uk = "Обігніть її вільний край, а тоді спустіться назад, у кишеню за нею.",
    };
    pub const there_it_is_a_septic_thrombus: T = .{
        .en = "There it is. A septic thrombus, and it's alive: three biofilm colonies, four fibrin cables holding it in place.",
        .uk = "Ось він. Септичний тромб, і він живий: три колонії в біоплівці й чотири фібринові тяжі, що тримають його на місці.",
    };
    pub const colonies_first: T = .{ .en = "Colonies first — they re-knit whatever you cut.", .uk = "Спершу колонії: вони зрощують усе, що ви переріжете." };
    pub const its_loose_and_drifting: T = .{ .en = "It's loose and drifting. Rounds on both arms!", .uk = "Він відірвався і дрейфує. Заряди на обидві руки!" };
    pub const dissolve_it_before_it_leaves: T = .{ .en = "Dissolve it before it leaves the pocket.", .uk = "Розчиніть його, доки він не вийшов із кишені." };
    pub const the_cusp_is_moving: T = .{
        .en = "The cusp is moving. That valve works again, and the pressure in her leg is already falling.",
        .uk = "Стулка рухається. Клапан знову працює, і тиск у її нозі вже падає.",
    };
    pub const sync_servo_is_live: T = .{
        .en = "Sync Servo is live. Trigger both arms within a tenth of a second and they land as one blow, ten times as hard.",
        .uk = "Синхросерво ввімкнено. Запустіть обидві руки з різницею до десятої частки секунди — і вони вдарять як одна, удесятеро сильніше.",
    };
    pub const put_both_arms_on_punch: T = .{ .en = "Put both arms on Punch and try it on the way to the marker.", .uk = "Поставте обидві руки на «Удар» і спробуйте дорогою до маркера." };
    pub const last_stretch: T = .{
        .en = "Last stretch: the junction with the femoral vein is half a centimetre ahead.",
        .uk = "Остання ділянка: до впадіння у стегнову вену — пів сантиметра.",
    };
    pub const no_flow_at_all: T = .{
        .en = "Feel that? No flow at all. Something has this vein corked. Find it and identify it.",
        .uk = "Відчуваєте? Течії немає зовсім. Щось закоркувало цю вену. Знайдіть і розпізнайте, що саме.",
    };
    pub const a_stone_in_the_only_channel: T = .{
        .en = "A stone, in the only channel through an old scar. Rounds won't touch calcium.",
        .uk = "Камінь — у єдиному каналі крізь старий рубець. Кальцій заряди не беруть.",
    };
    pub const both_arms_to_punch: T = .{ .en = "Both arms to Punch, and land them together.", .uk = "Обидві руки — на «Удар», і бийте ними водночас." };
    pub const its_through_hold_on: T = .{ .en = "It's through — hold on!", .uk = "Пробито — тримайтеся!" };
    pub const fine_grit: T = .{
        .en = "Fine grit. The lung capillaries will catch it and macrophages will clear it. Ride the flow out.",
        .uk = "Дрібний пісок. Його затримають капіляри легень і приберуть макрофаги. Виходьте за течією.",
    };
    /// The two transits of chapter 1, in order. Each names the distance its transit covers, in whole
    /// centimetres as the HUD's location readout measures it; a test in game.zig holds the two together.
    pub const tempo_link_down = [2]T{
        .{
            .en = "Tempo link down. Eleven centimetres in three seconds — don't blink.",
            .uk = "Вимикаю сповільнення часу. Одинадцять сантиметрів за три секунди — не кліпайте.",
        },
        .{
            .en = "Tempo link down again. Eighteen centimetres in three seconds — hold on.",
            .uk = "Знову вимикаю сповільнення часу. Вісімнадцять сантиметрів за три секунди — тримайтеся.",
        },
    };
    pub const reflux_back_off: T = .{ .en = "Reflux — the cusps are closing. Back off!", .uk = "Рефлюкс — стулки змикаються. Назад!" };
    pub const nothing_under_your_reticle: T = .{
        .en = "Nothing under your reticle. Point at something and ask again.",
        .uk = "Під прицілом нічого немає. Наведіть його на щось і спитайте ще раз.",
    };
    pub const thats_the_bulge_itself: T = .{ .en = "That's the bulge itself. The flap inside it is what I'm after.", .uk = "Це сам випин. Мені потрібна заслінка всередині нього." };
    pub const keep_an_eye_out_for_more: T = .{
        .en = "Keep an eye out for more that look wrong. I want to know how many.",
        .uk = "Пильнуйте, чи не трапляться ще такі, що виглядають не так. Хочу знати, скільки їх.",
    };
    pub const three_immature_cells: T = .{
        .en = "Three immature cells in one vein. Her marrow is emptying its reserves — that's the sepsis.",
        .uk = "Три незрілі клітини в одній вені. Її кістковий мозок спустошує резерви — це сепсис.",
    };
    pub const the_femurs_nutrient_vein: T = .{
        .en = "The femur's nutrient vein drains into the vessel you're about to join. I've logged the route. If she gets through today, I'd like to see where they are made.",
        .uk = "Живильна вена стегнової кістки впадає в судину, до якої ви зараз вийдете. Я записала маршрут. Якщо вона переживе сьогоднішній день, я хотіла б побачити, де вони утворюються.",
    };
    pub const drills_overheated: T = .{
        .en = "Drill's overheated. Let it cool — or share the work between both arms.",
        .uk = "Свердло перегрілося. Дайте йому охолонути — або розподіліть роботу між обома руками.",
    };
    pub const one_arm_only_chips_it: T = .{ .en = "One arm only chips it. Both together.", .uk = "Одна рука лише відколює крихти. Обидві разом." };
    pub const dont_hit_the_clot_it_sheds: T = .{ .en = "Don't hit the clot — it sheds!", .uk = "Не бийте по тромбу — він кришиться!" };
    pub const its_open_fire_into_it: T = .{ .en = "It's open — fire into it!", .uk = "Відкрито — стріляйте всередину!" };
    pub const not_the_clot_body_it_fragments: T = .{ .en = "Not the clot body — it fragments!", .uk = "Не в тіло тромбу — він розпадається на уламки!" };
    pub const thats_my_needle_youre_drilling: T = .{ .en = "That's my needle you're drilling.", .uk = "Ви свердлите мою голку." };
    pub const fragments_loose_dissolve_them: T = .{ .en = "Fragments loose — dissolve them!", .uk = "Уламки відірвалися — розчиніть їх!" };
    pub const colonies_are_gone: T = .{
        .en = "Colonies are gone. Now the cables: drill each one through. I'll call the fragments.",
        .uk = "Колоній більше немає. Тепер тяжі: пересвердліть кожен. Про уламки я попереджу.",
    };
    pub const one_down_same_again: T = .{ .en = "One down. Same again.", .uk = "Один є. Далі так само." };
    pub const the_slime_is_soaking_up_rounds: T = .{
        .en = "The slime is soaking up your rounds. Open it with the drill and fire through the hole — both arms at once.",
        .uk = "Слиз поглинає ваші заряди. Розкрийте його свердлом і стріляйте в отвір — обома руками водночас.",
    };
    pub const its_dissolving: T = .{ .en = "It's dissolving. Keep both arms on it.", .uk = "Він розчиняється. Не відводьте від нього жодної руки." };
    pub const see_it_knitting_back: T = .{
        .en = "See it knitting back? That's coagulase. Kill the colonies first.",
        .uk = "Бачите, як він зростається? Це коагулаза. Спершу знищте колонії.",
    };
    pub const one_got_past_you: T = .{
        .en = "One got past you. That's in her lungs now; we will pay for it later.",
        .uk = "Один проскочив повз вас. Тепер він у її легенях; за це ми заплатимо пізніше.",
    };
    pub const its_in_the_stream: T = .{ .en = "It's in the stream. That's a massive embolus.", .uk = "Він у потоці. Це масивний ембол." };
    pub const the_stones_colonised_company: T = .{ .en = "The stone's colonised — company!", .uk = "Камінь заселений — у нас гості!" };
    pub const its_glowing_shoot_it_or_move: T = .{ .en = "It's glowing — shoot it or move!", .uk = "Воно світиться — стріляйте або відходьте!" };
    pub const if_you_want_a_pointer: T = .{ .en = "If you want a pointer, press {@hint}.", .uk = "Якщо потрібна підказка, натисніть {@hint}." };
    pub const youre_out: T = .{
        .en = "You're out. This is the great saphenous vein: 3.6 millimetres across, and to you a cathedral.",
        .uk = "Ви вийшли. Це велика підшкірна вена: 3,6 міліметра в діаметрі, а для вас — собор.",
    };
    pub const good_the_marker_is_ahead: T = .{ .en = "Good. The marker is ahead of you — fly through it.", .uk = "Добре. Маркер попереду — пролетіть крізь нього." };
    pub const thats_it_youll_feel_the_difference: T = .{ .en = "That's it. You'll feel the difference on anything hard.", .uk = "Саме так. На всьому твердому ви відчуєте різницю." };
    pub const femoral_vein_the_leg_is_done: T = .{ .en = "Femoral vein. The leg is done.", .uk = "Стегнова вена. З ногою закінчено." };

    pub const and_youre_through: T = .{
        .en = "And you're through. Femoral vein, heart, lungs, heart again, down the aorta and out a capillary. She felt none of it.",
        .uk = "От ви й на місці. Стегнова вена, серце, легені, знову серце, вниз аортою і назовні з капіляра. Вона нічого з цього не відчула.",
    };
    pub const this_is_the_jejunum: T = .{
        .en = "This is the jejunum, the middle stretch of the small intestine, just past the duodenum. You came out of the tip of one of these fingers.",
        .uk = "Це порожня кишка, середній відділ тонкої кишки, одразу за дванадцятипалою. Ви вийшли з кінчика одного з цих пальців.",
    };
    pub const look_around_before_you_move: T = .{
        .en = "Look around before you move. Put your reticle on one of the fingers and press {@examine}.",
        .uk = "Роззирніться, перш ніж рухатися. Наведіть приціл на один із пальців і натисніть {@examine}.",
    };
    pub const now_feel_the_stream: T = .{
        .en = "Now feel the stream. Up here it will carry you a millimetre a second the wrong way. Between the villi it barely moves.",
        .uk = "Тепер відчуйте течію. Тут, нагорі, вона понесе вас не в той бік — міліметр за секунду. Між ворсинками вона ледве рухається.",
    };
    pub const go_down_all_the_way: T = .{ .en = "Go down. All the way to the floor.", .uk = "Спускайтеся. Аж до самого дна." };
    pub const contraction_ring_coming: T = .{
        .en = "Contraction ring, coming from upstream. Stay down between them.",
        .uk = "Кільце скорочення, іде до вас за течією. Залишайтеся внизу, між ворсинками.",
    };
    pub const watch_the_roof: T = .{
        .en = "Watch the roof. That is the far wall of the gut closing on this one.",
        .uk = "Дивіться на стелю. Це протилежна стінка кишки змикається з цією.",
    };
    pub const that_happens_every_half_minute: T = .{
        .en = "That happens every half minute. The ring always comes from upstream; when I call it, you go down.",
        .uk = "Так буває щопівхвилини. Кільце завжди приходить за течією; щойно я попереджу — спускайтеся.",
    };
    pub const now_the_job: T = .{
        .en = "Now the job. Rotavirus is inside her own cells at the tips, and from outside an infected cell looks like any other. Fly to the marker, get above the tips and scan: {@examine}.",
        .uk = "Тепер до справи. Ротавірус сидить у її власних клітинах на верхівках, а ззовні заражена клітина нічим не відрізняється від інших. Летіть до маркера, підніміться над верхівками і скануйте: {@examine}.",
    };
    pub const there_the_swollen_ones: T = .{
        .en = "There. The swollen ones. Punch each one out of the sheet, then shoot it once it floats free.",
        .uk = "Ось. Оті набряклі. Вибийте кожну з епітеліального пласта, а коли вона попливе вільно — стріляйте.",
    };
    pub const one_arm_on_punch_one_on_shoot: T = .{
        .en = "One arm on Punch, one on Shoot. And scan anything small before you fire at it.",
        .uk = "Одна рука — «Удар», друга — «Постріл». І скануйте все дрібне, перш ніж у нього стріляти.",
    };
    pub const that_villus_is_clean: T = .{
        .en = "That villus is clean, and the fever curve just bent. One more site upstream. Stay low on the way: the marker is past the next rows.",
        .uk = "Ця ворсинка чиста, і температурна крива щойно пішла вниз. Ще один осередок вище за течією. Дорогою тримайтеся низько: маркер — за наступними рядами.",
    };
    pub const upstream_the_villi_are_gone: T = .{
        .en = "Upstream of here the villi are gone, and so is your shelter. This is what the tether is for.",
        .uk = "Вище за течією ворсинок немає, а з ними й вашого сховку. Ось для чого потрібен трос.",
    };
    pub const aim_at_a_villus_within_reach: T = .{
        .en = "Aim at a villus within reach and press {@tether}. It reels you in and holds you there. {@tether} again lets go.",
        .uk = "Наведіть приціл на ворсинку в межах досяжності й натисніть {@tether}. Трос підтягне вас і втримає на місці. Ще раз {@tether} — відпустить.",
    };
    pub const good_now_go_upstream: T = .{
        .en = "Good. Now go upstream through the stripped stretch. Aim at the floor ahead, {@tether}, and let it pull you. Then the next point.",
        .uk = "Добре. Тепер — проти течії через оголену ділянку. Наведіть приціл на дно попереду, {@tether}, і дайте тросу вас підтягнути. Потім наступна точка.",
    };
    pub const youre_across: T = .{ .en = "You're across. The villi here are whole again.", .uk = "Ви перебралися. Тут ворсинки знову цілі." };
    pub const the_marker_takes_you_up: T = .{
        .en = "The marker takes you up the lumen on the tether: duodenum, then the stomach.",
        .uk = "Маркер поведе вас на тросі вгору просвітом: дванадцятипала кишка, далі шлунок.",
    };
    pub const youre_on_a_tip: T = .{ .en = "You're on a tip — get down between them!", .uk = "Ви на верхівці — спускайтеся між ворсинки!" };
    pub const the_stream_has_you: T = .{ .en = "The stream has you. Tether to the floor!", .uk = "Вас зносить течією. Чіпляйтеся тросом за дно!" };
    pub const nothing_to_hide_behind_here: T = .{ .en = "Nothing to hide behind here. Back downstream, into the villi.", .uk = "Тут нема за чим сховатися. Назад за течією, у ворсинки." };
    pub const youre_in_the_stream: T = .{ .en = "You're in the stream. Down, between the villi.", .uk = "Ви в потоці. Униз, між ворсинки." };
    pub const holding_feel_that: T = .{
        .en = "Holding. Feel that? The stream is still there and you are not moving.",
        .uk = "Тримає. Відчуваєте? Течія нікуди не зникла, а ви не рухаєтеся.",
    };
    pub const nothing_in_reach_to_hold: T = .{
        .en = "Nothing in reach to hold. The line is 0.4 millimetres.",
        .uk = "У межах досяжності нема за що зачепитися. Довжина троса — 0,4 міліметра.",
    };
    pub const more_of_them_same_again: T = .{ .en = "More of them. Same again.", .uk = "Ще кілька. Так само." };
    pub const resolved_green_rods_are_hers: T = .{ .en = "Resolved. Green rods are hers. Anything magenta is virus.", .uk = "Розпізнано. Зелені палички — її власні. Усе пурпурове — вірус." };
    pub const the_safest_place_in_the_gut: T = .{ .en = "And that is the safest place in the gut.", .uk = "А це — найбезпечніше місце в кишці." };
    pub const not_in_the_sheet: T = .{ .en = "Not in the sheet! Punch it out first.", .uk = "Не в пласті! Спершу вибийте її." };
    pub const that_one_burst: T = .{
        .en = "That one burst before you got to it. Every bleb it threw is looking for a clean tip.",
        .uk = "Ця луснула раніше, ніж ви до неї дісталися. Кожна везикула, яку вона викинула, шукає чисту верхівку.",
    };
    pub const those_were_hers: T = .{ .en = "Those were hers. Scan before you fire.", .uk = "Це були її власні. Скануйте, перш ніж стріляти." };
    pub const domes_gone: T = .{
        .en = "Dome's gone. Clear what it threw and hold still a moment.",
        .uk = "Купола більше немає. Приберіть те, що він викинув, і хвильку не рухайтеся.",
    };
    pub const out_and_the_sheet_has_closed: T = .{
        .en = "Out, and the sheet has closed behind it. Now shoot it before it bursts.",
        .uk = "Вийшла, і пласт за нею зімкнувся. Тепер стріляйте, поки вона не луснула.",
    };
    pub const half_of_them: T = .{ .en = "Half of them. Keep that rhythm: out, then down.", .uk = "Половина є. Тримайте ритм: вибити, потім збити." };
    pub const mucus_it_soaks_up_rounds: T = .{
        .en = "Mucus. It soaks up rounds the way the biofilm did. Drill it open and fire through the hole.",
        .uk = "Слиз. Він поглинає заряди так само, як біоплівка. Розсвердліть його і стріляйте в отвір.",
    };
    pub const not_the_crypts: T = .{ .en = "Not the crypts. Those stem cells are her recovery.", .uk = "Тільки не крипти. Ці стовбурові клітини — її одужання." };
    pub const dont_guess_at_tips: T = .{
        .en = "Don't guess at tips. Scan, then act on what lights up.",
        .uk = "Не бийте по верхівках навмання. Скануйте, а тоді працюйте з тим, що підсвітилося.",
    };
    pub const it_flares_before_it_darts: T = .{ .en = "It flares before it darts. Move when it flares.", .uk = "Перед кидком вона спалахує. Щойно спалахне — відходьте." };
    pub const a_bleb_reached_a_clean_tip: T = .{
        .en = "A bleb reached a clean tip. There is a new infected cell up there and you will need the scan to find it.",
        .uk = "Везикула дісталася чистої верхівки. Там тепер нова заражена клітина, і без сканування ви її не знайдете.",
    };
    pub const ring_coming_stay_on_the_line: T = .{ .en = "Ring coming. Stay on the line and stay low.", .uk = "Іде кільце. Тримайтеся на тросі й не підіймайтеся." };
    pub const ring_coming_get_down: T = .{ .en = "Ring coming — get down.", .uk = "Іде кільце — униз." };
    pub const the_ring_washed_something_in: T = .{ .en = "The ring washed something in. Scan it before you decide.", .uk = "Кільце щось принесло. Проскануйте, перш ніж вирішувати." };
    pub const it_has_gone_over_you: T = .{
        .en = "And it has gone over you. The villi mesh and the spaces between stay open.",
        .uk = "От воно й пройшло над вами. Ворсинки заходять одна між одну, а проміжки між ними лишаються відкритими.",
    };
    pub const here_the_virus_killed_the_tips: T = .{
        .en = "Here. The virus killed the tip cells faster than the crypts could replace them: stubs, and nothing to brake the stream.",
        .uk = "Ось. Вірус убивав клітини верхівок швидше, ніж крипти встигали їх заміняти: самі пеньки, і течію нічим загальмувати.",
    };
    pub const lines_on: T = .{ .en = "Line's on. Next stop is acid.", .uk = "Трос закріплено. Наступна зупинка — кислота." };

    // ---- chapter 3: gastric antrum
    pub const through_the_pylorus: T = .{
        .en = "You're in. Back up the lumen on your own line, through the pylorus on a reflux wave, and into the gel before the acid found you.",
        .uk = "Ви на місці. Назад просвітом по власному тросу, крізь воротар на хвилі рефлюксу — і в гель, перш ніж вас знайшла кислота.",
    };
    pub const this_is_the_antrum: T = .{
        .en = "This is the antrum, the last centimetres of stomach before the pylorus. It grinds; that is most of what it does.",
        .uk = "Це антральний відділ, останні сантиметри шлунка перед воротарем. Він перетирає — це майже все, що він робить.",
    };
    pub const look_down_at_the_pits: T = .{
        .en = "Look down. The lining is a honeycomb of holes. Put your reticle on one and press {@examine}.",
        .uk = "Подивіться вниз. Слизова — суцільні стільники з отворів. Наведіть приціл на один і натисніть {@examine}.",
    };
    pub const you_are_inside_the_gel: T = .{
        .en = "You are flying inside the mucus gel. The cells under you pump bicarbonate into it, so it is neutral down here and pH 2 at the top, a third of a millimetre up.",
        .uk = "Ви летите всередині слизового гелю. Клітини під вами закачують у нього бікарбонат, тож тут, унизу, він нейтральний, а нагорі, за третину міліметра звідси, — pH 2.",
    };
    pub const climb_and_watch_the_ph: T = .{
        .en = "Climb until your pH reading drops below 4. Then come straight back down.",
        .uk = "Підіймайтеся, доки показник pH не впаде нижче від 4. А тоді одразу назад.",
    };
    pub const thats_acid_come_down: T = .{ .en = "That is acid, and that is your hull fizzing. Down. Now.", .uk = "Це кислота, а шипить ваш корпус. Униз. Негайно." };
    pub const the_hull_recovers_in_gel: T = .{
        .en = "Back in neutral gel the hull's oxide skin regrows. That mends acid etching and nothing else.",
        .uk = "У нейтральному гелі оксидна плівка корпусу відновлюється. Це лікує сліди кислоти — і більше нічого.",
    };
    pub const antral_wave_coming: T = .{
        .en = "Antral wave, coming up behind you. Here the two walls meet completely.",
        .uk = "Антральна хвиля, іде на вас іззаду. Тут дві стінки змикаються повністю.",
    };
    pub const get_into_a_pit: T = .{ .en = "The pits stay open. Get down into one and wait.", .uk = "Ямки лишаються відкритими. Спустіться в одну й чекайте." };
    pub const it_has_closed_over_you: T = .{
        .en = "And it has closed over you and gone on. Three of those a minute.",
        .uk = "От вона зімкнулася над вами й пішла далі. Таких три на хвилину.",
    };
    pub const the_walls_have_you: T = .{ .en = "You're between the walls. Slide into a pit!", .uk = "Ви між стінками. Зісковзніть у ямку!" };
    pub const the_ulcer_is_ahead: T = .{
        .en = "The ulcer is ahead of you, away from the pylorus, three millimetres off. Stay in the gel on the way.",
        .uk = "Виразка попереду, в бік від воротаря, за три міліметри. Дорогою тримайтеся в гелі.",
    };
    pub const corkscrews_in_the_gel: T = .{
        .en = "Movement in the gel. Helicobacter: corkscrews. The gel that slows everything else is where they swim best.",
        .uk = "У гелі щось рухається. Гелікобактер: штопори. Гель, що гальмує все інше, для них — найкраще місце для плавання.",
    };
    pub const they_outrun_your_rounds: T = .{
        .en = "See that? Your rounds drag in the gel and they don't. From any distance they are gone before the round arrives.",
        .uk = "Бачили? Ваші заряди в’язнуть у гелі, а вони — ні. З будь-якої відстані їх уже немає, коли заряд долітає.",
    };
    pub const strike_when_it_flares: T = .{
        .en = "It holds still to flare before it darts. That is your opening: shoot it then, or punch it.",
        .uk = "Перед кидком він завмирає і спалахує. Це ваш шанс: стріляйте саме тоді або бийте.",
    };
    pub const a_sync_punch_clears_them: T = .{
        .en = "Several at once: a Sync punch clears everything within arm's reach, gel or no gel.",
        .uk = "Коли їх кілька одразу — синхроудар змітає все на відстані руки, хоч у гелі, хоч без нього.",
    };
    pub const thats_the_ulcer: T = .{
        .en = "There is the ulcer. The heaped rim, and past it a crater through the lining with no gel over it at all.",
        .uk = "Ось виразка. Вал, а за ним — кратер крізь слизову, над яким зовсім немає гелю.",
    };
    pub const colonies_in_the_pits: T = .{
        .en = "Four pits along the margin are packed with Helicobacter, and while they are, the edge cannot heal. Clear them. Rounds work, the drill works, both together work fastest.",
        .uk = "Чотири ямки вздовж краю набиті гелікобактером, і поки це так, край не загоїться. Вичистіть їх. Діють заряди, діє свердло, а найшвидше — те й те разом.",
    };
    pub const the_gel_is_thin_here: T = .{
        .en = "The gel is thin here and the surface is acid. Do your waiting deep inside a pit.",
        .uk = "Гель тут тонкий, і на поверхні вже кислота. Перечікуйте глибоко в ямці.",
    };
    pub const their_ammonia: T = .{
        .en = "Look at your pH over a colonised pit: neutral. They split urea into ammonia to make their own shelter. Borrow it.",
        .uk = "Гляньте на pH над колонізованою ямкою: нейтральний. Вони розщеплюють сечовину до аміаку й роблять собі сховок. Скористайтеся ним.",
    };
    pub const one_pit_clean: T = .{
        .en = "One pit clean. The ammonia went with them, so that mouth is acid again. Move on.",
        .uk = "Одна ямка чиста. Аміак зник разом із ними, тож в усті знову кислота. Рухайтеся далі.",
    };
    pub const the_margin_is_clean: T = .{ .en = "The margin is clean. Now it can close.", .uk = "Край чистий. Тепер він зможе закритися." };
    pub const mind_the_pit_walls: T = .{
        .en = "Mind the pit walls. The neck of each pit is where this lining renews itself.",
        .uk = "Обережно зі стінками ямок. У шийці кожної ямки ця слизова оновлюється.",
    };
    pub const wave_coming_into_a_pit: T = .{ .en = "Wave coming. Into a pit.", .uk = "Іде хвиля. У ямку." };
    pub const wave_coming_hold_the_bed: T = .{
        .en = "Wave coming. It will squirt acid back through the crater: tether to the bed.",
        .uk = "Іде хвиля. Вона жене кислоту назад крізь кратер: причепіться тросом до дна.",
    };
    pub const thats_acid_on_the_hull: T = .{ .en = "That's acid on bare hull. Get back into the gel.", .uk = "Кислота на голому корпусі. Повертайтеся в гель." };
    pub const coat_is_live: T = .{
        .en = "Buffer Coat is live. Twelve seconds of acid before it is spent, and it refills in neutral gel or in blood.",
        .uk = "Буферне покриття працює. Дванадцять секунд у кислоті, доки воно не вичерпається; відновлюється в нейтральному гелі або в крові.",
    };
    pub const the_vessel_is_in_the_bed: T = .{
        .en = "With the colonies gone the slough has lifted, and the vessel under it is bleeding freely. It is in the bed of the crater, half a millimetre down. No gel, no pits. Go.",
        .uk = "Колоній немає, наліт відійшов, і судина під ним кровить на повну. Вона на дні кратера, на пів міліметра нижче. Ні гелю, ні ямок. Уперед.",
    };
    pub const coats_spent: T = .{ .en = "Coat's spent. Get to something neutral.", .uk = "Покриття вичерпано. Шукайте щось нейтральне." };
    pub const there_it_is_pulsing: T = .{
        .en = "There. An arteriole with one wall eaten away, pulsing. Stay out of the jet. The blood around it is neutral, so you can work here.",
        .uk = "Ось. Артеріола з роз’їденою стінкою, пульсує. Не потрапляйте під струмінь. Кров довкола неї нейтральна, тож тут можна працювати.",
    };
    pub const press_it_then_weld: T = .{
        .en = "Coaptive cautery. One arm on PUNCH to press the walls together, the other on DRILL to weld them while they are pressed. Both at once.",
        .uk = "Коаптаційна коагуляція. Одна рука — УДАР, щоб притиснути стінки одну до одної, друга — СВЕРДЛО, щоб зварити їх, поки вони притиснуті. Обидві разом.",
    };
    pub const heat_alone_wont_hold: T = .{
        .en = "Heat alone won't hold. While blood runs through it, the blood carries the heat away. Press it shut with the other arm.",
        .uk = "Самого нагріву замало. Поки крізь судину тече кров, вона забирає тепло. Притисніть її другою рукою.",
    };
    pub const its_pressed_heat_it_now: T = .{ .en = "It's pressed flat. Heat it now, before it springs open.", .uk = "Її притиснуто. Грійте зараз, поки вона не розкрилася." };
    pub const half_welded: T = .{
        .en = "Half welded. Let the bit cool if you must; the weld keeps for a few seconds.",
        .uk = "Наполовину зварено. Якщо треба, дайте свердлу охолонути: шов кілька секунд протримається.",
    };
    pub const not_rounds_at_a_vessel: T = .{ .en = "Not rounds. You will only open it further.", .uk = "Тільки не заряди. Ви лише розкриєте її ще більше." };
    pub const its_sealed: T = .{ .en = "Sealed. Nothing is coming through it. The bleed is stopped.", .uk = "Заварено. Крізь неї нічого не проходить. Кровотечу зупинено." };
    pub const marker_on_a_venule: T = .{
        .en = "Your way out is the venule the crater has laid bare, just beside you. Without the blood this bed is acid again, so don't linger.",
        .uk = "Ваш вихід — венула, яку оголив кратер, зовсім поруч. Без крові на цьому дні знову кислота, тож не затримуйтеся.",
    };
    pub const gastric_vein_next: T = .{
        .en = "You're in. Gastric vein, portal vein, liver, heart, lungs, and round again to her right kidney.",
        .uk = "Ви всередині. Шлункова вена, ворітна вена, печінка, серце, легені — і ще одне коло, до її правої нирки.",
    };

    pub const link_re_established: T = .{ .en = "Link re-established. You're back at the last checkpoint.", .uk = "Зв’язок відновлено. Ви знову на останній контрольній точці." };
};

/// What H says, by stage: three levels from a nudge to exact keys, or one line where a stage needs no more.
pub const hint = struct {
    pub const needle = [3]T{
        .{ .en = "The light at the end of the tube is the bevel. Head for it.", .uk = "Світло в кінці трубки — це зріз голки. Летіть до нього." },
        .{
            .en = "Hold W. Steer with the mouse or the arrow keys.",
            .uk = "Утримуйте W. Керуйте мишею або стрілками.",
            .pad = &.{ .en = "Push the left stick forward. Steer with the right stick.", .uk = "Відхиліть лівий стік уперед. Керуйте правим стіком." },
        },
        .{
            .en = "Hold W and Shift together and keep the bright opening in the middle of your view until the walls fall away.",
            .uk = "Утримуйте разом W і Shift і тримайте світлий отвір у центрі поля зору, доки стінки не розступляться.",
            .pad = &.{
                .en = "Push the left stick forward, click {@boost} to boost, and keep the bright opening in the middle of your view until the walls fall away.",
                .uk = "Відхиліть лівий стік уперед, натисніть {@boost} для прискорення і тримайте світлий отвір у центрі поля зору, доки стінки не розступляться.",
            },
        },
    };
    pub const flow_wall = [3]T{
        .{
            .en = "Any wall will do. Pick a direction across the stream and keep going.",
            .uk = "Підійде будь-яка стінка. Оберіть напрямок упоперек потоку й летіть.",
        },
        .{
            .en = "Turn until the diamond marker is ahead, then hold W with Shift. It is over a millimetre away.",
            .uk = "Повертайтеся, доки ромбовий маркер не опиниться попереду, тоді утримуйте W із Shift. До нього понад міліметр.",
            .pad = &.{
                .en = "Turn until the diamond marker is ahead, then push the left stick forward and click {@boost}. It is over a millimetre away.",
                .uk = "Повертайтеся, доки ромбовий маркер не опиниться попереду, тоді відхиліть лівий стік уперед і натисніть {@boost}. До нього понад міліметр.",
            },
        },
        .{
            .en = "Face the marker, hold Shift+W for about five seconds, and stop when the cobbled wall fills your view.",
            .uk = "Станьте лицем до маркера, утримуйте Shift+W секунд п’ять і зупиніться, коли брукована стінка заповнить поле зору.",
            .pad = &.{
                .en = "Face the marker, click {@boost} and hold the left stick forward for about five seconds, and stop when the cobbled wall fills your view.",
                .uk = "Станьте лицем до маркера, натисніть {@boost} і секунд п’ять тримайте лівий стік відхиленим уперед, а коли брукована стінка заповнить поле зору — зупиніться.",
            },
        },
    };
    pub const flow_core = [3]T{
        .{
            .en = "The core is the axis of the vein, as far from every wall as you can get.",
            .uk = "Середина потоку — це вісь вени, якнайдалі від усіх стінок.",
        },
        .{
            .en = "Turn your back to the wall and thrust until the flow readout climbs.",
            .uk = "Розверніться спиною до стінки й летіть, доки показник потоку не почне зростати.",
        },
        .{
            .en = "Fly away from the wall until FLOW on the top right reads above 150.",
            .uk = "Летіть від стінки, доки ПОТІК угорі праворуч не перевищить 150.",
        },
    };
    pub const to_valve1 = [3]T{
        .{ .en = "Downstream is the way the cells are moving.", .uk = "За течією — це туди, куди рухаються клітини." },
        .{
            .en = "Stay in the core and let it carry you; add W to go faster.",
            .uk = "Тримайтеся середини, і потік понесе вас сам; додайте W, щоб летіти швидше.",
            .pad = &.{
                .en = "Stay in the core and let it carry you; push the left stick forward to go faster.",
                .uk = "Тримайтеся середини, і потік понесе вас сам; відхиліть лівий стік уперед, щоб летіти швидше.",
            },
        },
        .{
            .en = "Follow the diamond marker. The valve is where the wall swells outward.",
            .uk = "Летіть за ромбовим маркером. Клапан там, де стінка випинається назовні.",
        },
    };
    pub const valve1_identify = [3]T{
        .{
            .en = "Two pale sheets hang inside the bulge. Those are what I mean.",
            .uk = "Усередині випину висять дві бліді пластинки. Про них і мова.",
        },
        .{
            .en = "Centre the reticle on one of the pale sheets — the label under the reticle changes — and press {@examine}.",
            .uk = "Наведіть приціл на одну з блідих пластинок — напис під прицілом зміниться — і натисніть {@examine}.",
        },
        .{
            .en = "Fly toward the marker, aim at a sheet until the reticle reads UNIDENTIFIED, press {@examine}.",
            .uk = "Летіть до маркера, цільтеся в пластинку, доки під прицілом не з’явиться НЕ РОЗПІЗНАНО, і натисніть {@examine}.",
        },
    };
    pub const valve1_pass = [3]T{
        .{
            .en = "The gap between the two cusps opens and closes with the pump. The gauge on the right shows the cycle.",
            .uk = "Щілина між двома стулками відкривається й закривається в такт м’язовій помпі. Індикатор праворуч показує цикл.",
        },
        .{
            .en = "Wait upstream of the cusps until they swing back against the wall, then go through the middle.",
            .uk = "Зачекайте перед стулками, доки вони не відхиляться до стінки, а тоді проходьте посередині.",
        },
        .{
            .en = "Hover near the axis. When VALVE on the right reads OPEN, hold Shift+W straight down the centre.",
            .uk = "Зависніть біля осі. Коли праворуч з’явиться КЛАПАНИ ВІДКРИТІ, утримуйте Shift+W і летіть прямо по центру.",
            .pad = &.{
                .en = "Hover near the axis. When VALVE on the right reads OPEN, click {@boost} and fly straight down the centre.",
                .uk = "Зависніть біля осі. Коли праворуч з’явиться КЛАПАНИ ВІДКРИТІ, натисніть {@boost} і летіть прямо по центру.",
            },
        },
    };
    pub const neutrophil = [3]T{
        .{
            .en = "They are on the wall, not in the stream. Go and look at the wall.",
            .uk = "Вони на стінці, а не в потоці. Підлетіть і огляньте стінку.",
        },
        .{
            .en = "Fly to the wall a little further downstream. The pale, slightly spiky spheres are the ones.",
            .uk = "Підлетіть до стінки трохи далі за течією. Вам потрібні бліді, ледь шпичасті кульки.",
        },
        .{
            .en = "Hug the wall past the valve, put the reticle on a pale sphere larger than a red cell, press {@examine}.",
            .uk = "Тримайтеся стінки за клапаном, наведіть приціл на бліду кульку, більшу за еритроцит, і натисніть {@examine}.",
        },
    };
    pub const staph = [3]T{
        .{ .en = "Gold clusters, small. They come to you.", .uk = "Золотаві скупчення, дрібні. Вони самі до вас прийдуть." },
        .{
            .en = "Point the reticle at a cluster and hold {@arm_left}. When one glows it is about to lunge: shoot it or sidestep.",
            .uk = "Наведіть приціл на скупчення й утримуйте {@arm_left}. Якщо котресь засвітилося, воно зараз кинеться: стріляйте або ухиляйтеся вбік.",
        },
        .{
            .en = "Hold {@arm_left} and sweep the reticle over each gold cluster. Strafe with A or D whenever one flares.",
            .uk = "Утримуйте {@arm_left} і ведіть прицілом по кожному золотавому скупченню. Щойно котресь спалахне — зміщуйтеся вбік клавішею A або D.",
            .pad = &.{
                .en = "Hold {@arm_left} and sweep the reticle over each gold cluster. Strafe with the left stick whenever one flares.",
                .uk = "Утримуйте {@arm_left} і ведіть прицілом по кожному золотавому скупченню. Щойно котресь спалахне — зміщуйтеся вбік лівим стіком.",
            },
        },
    };
    pub const tools = [3]T{
        .{
            .en = "The panels at the bottom corners show what each arm is carrying.",
            .uk = "Панелі в нижніх кутах показують, що встановлено на кожній руці.",
        },
        .{
            .en = "Press {@tool_left} or {@tool_right} until one panel reads DRILL and the other SHOOT.",
            .uk = "Натискайте {@tool_left} або {@tool_right}, доки на одній панелі не буде СВЕРДЛО, а на другій — ПОСТРІЛ.",
        },
        .{
            .en = "Press {@tool_right} once: the right arm goes from PUNCH to DRILL. Leave the left on SHOOT. Then fly to the ring.",
            .uk = "Натисніть {@tool_right} один раз: права рука перемкнеться з УДАР на СВЕРДЛО. На лівій залиште ПОСТРІЛ. Потім летіть до кільця.",
        },
    };
    pub const v2_approach = [3]T{
        .{
            .en = "The pocket is the space between that cusp and the wall. Its opening faces downstream.",
            .uk = "Кишеня — це простір між тією стулкою і стінкою. Її вхід обернений за течією.",
        },
        .{
            .en = "Fly downstream past the cusp's free edge, then turn back upstream above it.",
            .uk = "Пролетіть за течією повз вільний край стулки, а тоді розверніться проти течії над нею.",
        },
        .{
            .en = "Follow the marker over the edge of the upper cusp, turn around, and fly back along the wall side of the cusp until you see the clot.",
            .uk = "Летіть за маркером через край верхньої стулки, розверніться й рухайтеся назад уздовж її пристінкового боку, доки не побачите тромб.",
        },
    };
    pub const treat_colonies = [3]T{
        .{
            .en = "The gold domes on the clot are the colonies. Rounds alone bounce off the slime.",
            .uk = "Золотаві куполи на тромбі — це колонії. Самі лише заряди від слизу відскакують.",
        },
        .{
            .en = "One arm on Drill, one on Shoot. Touch a dome and hold the drill in it; fire the other arm at the same time.",
            .uk = "Одна рука — «Свердло», друга — «Постріл». Торкніться купола й тримайте в ньому свердло; водночас стріляйте другою рукою.",
        },
        .{
            .en = "Fly to a gold dome until it fills the view. Hold the Drill arm's key until the dome turns clear, and hold the Shoot arm's key with it. Eight rounds kill it.",
            .uk = "Підлетіть до золотавого купола, щоб він заповнив поле зору. Утримуйте клавішу руки зі свердлом, доки купол не стане прозорим, і разом із нею — клавішу руки з пострілом. Вісім зарядів знищать колонію.",
            .pad = &.{
                .en = "Fly to a gold dome until it fills the view. Hold the Drill arm's trigger until the dome turns clear, and hold the Shoot arm's trigger with it. Eight rounds kill it.",
                .uk = "Підлетіть до золотавого купола, щоб він заповнив поле зору. Утримуйте тригер руки зі свердлом, доки купол не стане прозорим, і разом із ним — тригер руки з пострілом. Вісім зарядів знищать колонію.",
            },
        },
    };
    pub const treat_cables = [3]T{
        .{
            .en = "The pale cables run from the clot to the wall and to the cusp. They are what holds it.",
            .uk = "Бліді тяжі тягнуться від тромбу до стінки й до стулки. Саме вони його тримають.",
        },
        .{
            .en = "Fly up to a cable and hold the drill on it for three seconds. Keep the other arm on Shoot for whatever comes at you.",
            .uk = "Підлетіть до тяжа й тримайте на ньому свердло три секунди. Другу руку залиште на «Постріл» — для всього, що на вас полетить.",
        },
        .{
            .en = "Follow the marker to a cable, press the drill against it and hold. When fragments break off, shoot each one three times before it reaches the stream.",
            .uk = "Летіть за маркером до тяжа, притисніть до нього свердло й тримайте. Коли відколюватимуться уламки, влучте в кожен тричі, доки він не дістався потоку.",
        },
    };
    pub const lyse_core = [3]T{
        .{ .en = "Nothing shields it now. Rounds work.", .uk = "Тепер його ніщо не захищає. Заряди діють." },
        .{
            .en = "Put both arms on Shoot and hold both keys on the clot.",
            .uk = "Поставте обидві руки на «Постріл» і утримуйте обидві клавіші, цілячись у тромб.",
            .pad = &.{
                .en = "Put both arms on Shoot and hold both triggers on the clot.",
                .uk = "Поставте обидві руки на «Постріл» і утримуйте обидва тригери, цілячись у тромб.",
            },
        },
        .{
            .en = "{@tool_left} and {@tool_right} until both panels read SHOOT. Aim at the clot, hold {@arm_left} and {@arm_right} until it is gone.",
            .uk = "{@tool_left} і {@tool_right}, доки на обох панелях не буде ПОСТРІЛ. Цільтеся в тромб і утримуйте {@arm_left} та {@arm_right}, доки він не зникне.",
        },
    };
    pub const freed: T = .{ .en = "Take a breath. She's better than she was.", .uk = "Переведіть подих. Їй уже краще, ніж було." };
    pub const to_ring2 = [3]T{
        .{ .en = "The marker is downstream of the valve, below the axis.", .uk = "Маркер — за клапаном за течією, нижче від осі." },
        .{
            .en = "Leave the pocket over the cusp's free edge and follow the diamond.",
            .uk = "Вийдіть із кишені через вільний край стулки й летіть за ромбом.",
        },
        .{
            .en = "Fly downstream out of the pocket, then follow the diamond marker to the ring and through it.",
            .uk = "Вилетіть із кишені за течією, далі — за ромбовим маркером до кільця і крізь нього.",
        },
    };
    pub const septum_find = [3]T{
        .{
            .en = "The vein is walled off ahead. Look for the one place the wall is not scar.",
            .uk = "Попереду вена перегороджена. Шукайте єдине місце, де перегородка — не рубець.",
        },
        .{
            .en = "Follow the web down and to the right until you find a pale stone set into it.",
            .uk = "Рухайтеся вздовж перетинки вниз і праворуч, доки не знайдете вмурований у неї блідий камінь.",
        },
        .{
            .en = "Fly downstream to the scar wall, find the chalk-white boulder in it, aim at it and press {@examine}.",
            .uk = "Летіть за течією до рубцевої стіни, знайдіть у ній крейдяно-білу брилу, наведіть на неї приціл і натисніть {@examine}.",
        },
    };
    pub const septum_break = [3]T{
        .{
            .en = "Brittle things break on impact. One arm is not enough impact.",
            .uk = "Крихке ламається від удару. Однієї руки для такого удару замало.",
        },
        .{
            .en = "Both arms on Punch. Get within arm's reach of the stone and press {@arm_left} and {@arm_right} at the same instant.",
            .uk = "Обидві руки — на «Удар». Підлетіть до каменя на відстань руки й натисніть {@arm_left} та {@arm_right} в одну мить.",
        },
        .{
            .en = "{@tool_left} and {@tool_right} until both panels read PUNCH. Fly until the stone fills the view, then tap {@arm_left} and {@arm_right} together. SYNC flashes when you get it. Five of those.",
            .uk = "{@tool_left} і {@tool_right}, доки на обох панелях не буде УДАР. Підлетіть, щоб камінь заповнив поле зору, і натисніть {@arm_left} та {@arm_right} разом. Коли вийде, спалахне СИНХРО. Таких ударів треба п’ять.",
        },
    };
    pub const exit: T = .{ .en = "Let the channel take you, then keep going downstream.", .uk = "Дайте каналу пронести вас, а далі рухайтеся за течією." };
    pub const ring: T = .{ .en = "Fly through the ring.", .uk = "Пролетіть крізь кільце." };
    pub const g_villus = [3]T{
        .{ .en = "Anything tall and cobbled is a villus.", .uk = "Усе високе й бруковане — це ворсинка." },
        .{
            .en = "Turn until one of the fingers is under the reticle, then press {@examine}.",
            .uk = "Повертайтеся, доки один із пальців не опиниться під прицілом, і натисніть {@examine}.",
        },
        .{
            .en = "Look down and to the side with the mouse or arrow keys until the reticle label appears on a villus. Press {@examine}.",
            .uk = "Мишею або стрілками подивіться вниз і вбік, доки на ворсинці не з’явиться напис під прицілом. Натисніть {@examine}.",
            .pad = &.{
                .en = "Look down and to the side with the right stick until the reticle label appears on a villus. Press {@examine}.",
                .uk = "Правим стіком подивіться вниз і вбік, доки на ворсинці не з’явиться напис під прицілом. Натисніть {@examine}.",
            },
        },
    };
    pub const g_descend = [3]T{
        .{ .en = "The stream is fast above the tips and still below them.", .uk = "Над верхівками течія швидка, а під ними її майже немає." },
        .{
            .en = "Follow the marker down into the gap between three villi. {@down} descends.",
            .uk = "Спускайтеся за маркером у проміжок між трьома ворсинками. Клавіша {@down} — униз.",
            .pad = &.{
                .en = "Follow the marker down into the gap between three villi. {@down} descends.",
                .uk = "Спускайтеся за маркером у проміжок між трьома ворсинками. Кнопка {@down} — униз.",
            },
        },
        .{
            .en = "Hold {@down} until the flow readout on the top right drops under 20 and the floor of pits is right below you.",
            .uk = "Утримуйте {@down}, доки показник течії вгорі праворуч не впаде нижче 20, а дно з ямками не опиниться просто під вами.",
        },
    };
    pub const g_wave = [3]T{
        .{ .en = "The ring only closes the lumen down to the tips.", .uk = "Кільце змикає просвіт лише до верхівок." },
        .{ .en = "Stay near the floor. Do not sit on top of a villus.", .uk = "Тримайтеся біля дна. Не сидіть на верхівці ворсинки." },
        .{
            .en = "Hold {@down} to stay on the crypt floor and wait. The roof comes down, passes over you and lifts again.",
            .uk = "Утримуйте {@down}, щоб лишатися на дні з криптами, і чекайте. Стеля опуститься, пройде над вами й підніметься знову.",
        },
    };
    pub const g_scan = [3]T{
        .{ .en = "Infected cells do not show until the scan reads them.", .uk = "Заражених клітин не видно, доки їх не зчитає скан." },
        .{
            .en = "Go to the marker, climb until you are level with the villus tips and press {@examine}. The pulse reaches 0.7 mm.",
            .uk = "Летіть до маркера, підніміться на рівень верхівок ворсинок і натисніть {@examine}. Імпульс сягає 0,7 мм.",
        },
        .{
            .en = "Fly to the diamond marker, hold Space until you are just above the tops of the villi, press {@examine}. Swollen magenta cells appear on the infected tips.",
            .uk = "Летіть до ромбового маркера, утримуйте Пробіл, доки не опинитеся трохи вище від верхівок ворсинок, і натисніть {@examine}. На заражених верхівках проявляться набряклі пурпурові клітини.",
            .pad = &.{
                .en = "Fly to the diamond marker, hold {@up} until you are just above the tops of the villi, press {@examine}. Swollen magenta cells appear on the infected tips.",
                .uk = "Летіть до ромбового маркера, утримуйте {@up}, доки не опинитеся трохи вище від верхівок ворсинок, і натисніть {@examine}. На заражених верхівках проявляться набряклі пурпурові клітини.",
            },
        },
    };
    pub const g_extrude = [3]T{
        .{
            .en = "A cell in the sheet is pushed out. A cell that is already out is shot.",
            .uk = "Клітину в пласті виштовхують. Клітину, що вже вийшла, розстрілюють.",
        },
        .{
            .en = "Get within arm's reach of a swollen cell and punch it. It floats off flashing: put rounds in it before it bursts. If the count is not complete, scan another tip.",
            .uk = "Підлетіть до набряклої клітини на відстань руки й ударте її. Вона попливе, блимаючи: всадіть у неї заряди, поки не луснула. Якщо лічильник не повний, проскануйте іншу верхівку.",
        },
        .{
            .en = "{@tool_left} and {@tool_right} until one panel reads PUNCH and the other SHOOT. Hover over a magenta cell, hit the Punch key, then hold the Shoot key on the cell that floats away. Press {@examine} near small organisms first: green are hers, magenta are virus.",
            .uk = "{@tool_left} і {@tool_right}, доки на одній панелі не буде УДАР, а на другій — ПОСТРІЛ. Зависніть над пурпуровою клітиною, натисніть клавішу удару, потім утримуйте клавішу пострілу, цілячись у клітину, що відпливає. Біля дрібних організмів спершу натискайте {@examine}: зелені — її власні, пурпурові — вірус.",
            .pad = &.{
                .en = "{@tool_left} and {@tool_right} until one panel reads PUNCH and the other SHOOT. Hover over a magenta cell, pull the Punch trigger, then hold the Shoot trigger on the cell that floats away. Press {@examine} near small organisms first: green are hers, magenta are virus.",
                .uk = "{@tool_left} і {@tool_right}, доки на одній панелі не буде УДАР, а на другій — ПОСТРІЛ. Зависніть над пурпуровою клітиною, натисніть тригер удару, потім утримуйте тригер пострілу, цілячись у клітину, що відпливає. Біля дрібних організмів спершу натискайте {@examine}: зелені — її власні, пурпурові — вірус.",
            },
        },
    };
    pub const g_factory = [3]T{
        .{ .en = "It is the colony from the vein again, in different clothes.", .uk = "Це знову та сама колонія з вени, тільки в іншому вбранні." },
        .{
            .en = "One arm on Drill, one on Shoot. Hold the drill in the dome and fire with the other arm once it opens.",
            .uk = "Одна рука — «Свердло», друга — «Постріл». Тримайте свердло в куполі, а щойно він розкриється, стріляйте другою рукою.",
        },
        .{
            .en = "Fly up to the mucus dome on the marked villus. Hold the Drill key with the bit in it; when I call it open, hold the Shoot key as well. Blebs will come at you: the drill holds its place if you look away to shoot them.",
            .uk = "Підлетіть до слизового купола на позначеній ворсинці. Утримуйте клавішу свердла, щоб воно працювало в куполі; коли я скажу, що він відкритий, утримуйте ще й клавішу пострілу. На вас полетять везикули: свердло лишиться на місці, якщо ви відвернетеся, щоб їх збити.",
            .pad = &.{
                .en = "Fly up to the mucus dome on the marked villus. Hold the Drill trigger with the bit in it; when I call it open, hold the Shoot trigger as well. Blebs will come at you: the drill holds its place if you look away to shoot them.",
                .uk = "Підлетіть до слизового купола на позначеній ворсинці. Утримуйте тригер свердла, щоб воно працювало в куполі; коли я скажу, що він відкритий, утримуйте ще й тригер пострілу. На вас полетять везикули: свердло лишиться на місці, якщо ви відвернетеся, щоб їх збити.",
            },
        },
    };
    pub const g_tether = [3]T{
        .{ .en = "The tether needs tissue to hold and it reaches 0.4 mm.", .uk = "Тросу потрібна тканина, щоб зачепитися, і сягає він на 0,4 мм." },
        .{ .en = "Put the reticle on a villus close by and press {@tether}.", .uk = "Наведіть приціл на ближню ворсинку й натисніть {@tether}." },
        .{
            .en = "Fly to within a couple of villus widths of any villus, aim at it, press {@tether}. Do it twice.",
            .uk = "Підлетіть до будь-якої ворсинки на відстань двох-трьох її ширин, наведіть приціл і натисніть {@tether}. Зробіть це двічі.",
        },
    };
    pub const g_flume = [3]T{
        .{ .en = "You cannot out-fly this stream. You can out-pull it.", .uk = "Цю течію не перелетіти. А от перетягнути її можна." },
        .{
            .en = "Aim at the floor ahead of you, upstream, and press {@tether}. When it has reeled you in, aim further on and press {@tether} again.",
            .uk = "Наведіть приціл на дно попереду, вище за течією, і натисніть {@tether}. Коли трос вас підтягне, наведіть далі й натисніть {@tether} знову.",
        },
        .{
            .en = "Face the marker. Look slightly down at the stubs about a third of a millimetre ahead, press {@tether}, wait until you stop, repeat. Do not release with nothing new to hold: the stream takes you straight back.",
            .uk = "Станьте лицем до маркера. Подивіться трохи вниз, на пеньки приблизно за третину міліметра попереду, натисніть {@tether}, дочекайтеся зупинки й повторіть. Не відпускайте трос, якщо нема за що зачепитися знову: течія одразу віднесе вас назад.",
        },
    };
    pub const g_exit: T = .{ .en = "Fly through the ring ahead of you.", .uk = "Пролетіть крізь кільце попереду." };
    pub const s_pits = [3]T{
        .{ .en = "The pits are the dark holes in the honeycomb under you.", .uk = "Ямки — це темні отвори в стільниках під вами." },
        .{
            .en = "Tilt down until a pit is under the reticle, then press {@examine}.",
            .uk = "Нахиляйте погляд униз, доки під прицілом не опиниться ямка, і натисніть {@examine}.",
        },
        .{
            .en = "Any part of the lining will do: put the reticle on the surface or on a hole in it and press {@examine}.",
            .uk = "Підійде будь-яка ділянка слизової: наведіть приціл на поверхню або на отвір у ній і натисніть {@examine}.",
        },
    };
    pub const s_gradient = [3]T{
        .{ .en = "The pH readout is at the top right. It falls as you rise.", .uk = "Показник pH — угорі праворуч. Що вище ви підіймаєтеся, то він нижчий." },
        .{
            .en = "Go up with {@up} until the reading is under 4, then down with {@down} until it is back near 7.",
            .uk = "Підіймайтеся — {@up}, доки показник не стане меншим за 4, а тоді спускайтеся — {@down}, доки він не повернеться до 7.",
        },
        .{
            .en = "Hold {@up} for about a second, wait for the hull bar to flicker, then hold {@down} until the surface stops you.",
            .uk = "Потримайте {@up} приблизно секунду, дочекайтеся, поки смуга корпусу замиготить, а тоді тримайте {@down}, доки вас не зупинить поверхня.",
        },
    };
    pub const s_wave = [3]T{
        .{ .en = "Under a wave the only open space is inside a pit.", .uk = "Під хвилею вільне місце є тільки всередині ямки." },
        .{
            .en = "Fly over the nearest dark hole and descend into it with {@down}. Stay below its mouth until the roof lifts.",
            .uk = "Зависніть над найближчим темним отвором і спустіться в нього — {@down}. Залишайтеся нижче від устя, доки стеля не підніметься.",
        },
        .{
            .en = "Or aim down into a pit and press {@tether}: the line pulls you in and holds you there.",
            .uk = "Або наведіть приціл у глиб ямки й натисніть {@tether}: трос затягне вас усередину й утримає.",
        },
    };
    pub const s_swim = [3]T{
        .{ .en = "Rounds fired from a distance never arrive. Let them come to you.", .uk = "Заряди, випущені здалеку, не долітають. Дайте їм підійти самим." },
        .{
            .en = "A swimmer stops and flares for most of a second before it darts. Shoot or punch it while it is flaring.",
            .uk = "Перед кидком плавець зупиняється і майже секунду спалахує. Стріляйте або бийте саме в цю мить.",
        },
        .{
            .en = "With PUNCH on both arms, trigger both at once when they are close: the Sync punch kills every swimmer within arm's reach.",
            .uk = "Поставте УДАР на обидві руки й запустіть обидві разом, коли вони близько: синхроудар убиває кожного плавця на відстані руки.",
        },
    };
    pub const s_margin = [3]T{
        .{
            .en = "The marker is over a colonised pit. Hover in its mouth: the pH there is neutral.",
            .uk = "Маркер стоїть над колонізованою ямкою. Зависніть у її усті: pH там нейтральний.",
        },
        .{
            .en = "From the mouth, fire straight down into the pale mass, or drill it. Both arms at once is quickest.",
            .uk = "З устя стріляйте просто вниз у бліду масу або свердліть її. Найшвидше — обома руками одночасно.",
        },
        .{
            .en = "Between pits you are in acid: cross quickly, and when a wave is called, drop into the nearest pit, cleared or not.",
            .uk = "Між ямками ви в кислоті: перелітайте швидко, а коли оголошено хвилю, пірнайте в найближчу ямку, чисту чи ні.",
        },
    };
    pub const s_cross = [3]T{
        .{
            .en = "The coat lasts twelve seconds in acid. The crater is less than that across.",
            .uk = "Покриття тримається в кислоті дванадцять секунд. Перелетіти кратер можна швидше.",
        },
        .{
            .en = "Follow the marker over the rim and down to the bed. Hold {@boost} to go faster.",
            .uk = "Летіть за маркером через вал і вниз, до дна. Тримайте {@boost}, щоб прискоритися.",
        },
        .{
            .en = "The blood around the vessel is neutral: once you are within a fifth of a millimetre of it, the coat refills.",
            .uk = "Кров довкола судини нейтральна: щойно ви опинитеся за п’яту частину міліметра від неї, покриття почне відновлюватися.",
        },
    };
    pub const s_cautery = [3]T{
        .{ .en = "Pressure and heat together. Either one alone does nothing.", .uk = "Тиск і нагрів разом. Окремо не діє ні те, ні те." },
        .{
            .en = "Put PUNCH on one arm and DRILL on the other. Come at the vessel from the side, out of the jet, until the drill bites; then hold both.",
            .uk = "Поставте УДАР на одну руку і СВЕРДЛО на другу. Підійдіть до судини збоку, поза струменем, доки свердло не візьметься; тоді тримайте обидві.",
        },
        .{
            .en = "Hold {@arm_left} and {@arm_right} together. Release the drill arm when HEAT is nearly full and hold it again when it has cooled; the weld keeps.",
            .uk = "Тримайте {@arm_left} і {@arm_right} разом. Відпустіть руку зі свердлом, коли НАГРІВ майже повний, і натисніть знову, коли воно охолоне; шов протримається.",
        },
    };
    pub const wait: T = .{ .en = "Wait for it.", .uk = "Зачекайте." };
};

/// The one-line objective at the top of the HUD, by stage.
pub const objective = struct {
    pub const needle: T = .{ .en = "Leave the cannula", .uk = "Вийдіть із канюлі" };
    pub const flow_wall: T = .{ .en = "Reach the vessel wall", .uk = "Дістаньтеся стінки судини" };
    pub const flow_core: T = .{ .en = "Return to the core of the stream", .uk = "Поверніться в середину потоку" };
    pub const to_valve1: T = .{ .en = "Follow the flow to the first valve", .uk = "Рухайтеся за течією до першого клапана" };
    pub const valve1_identify: T = .{ .en = "Identify the valve cusp — aim at it and press {@examine}", .uk = "Розпізнайте стулку клапана — наведіть приціл і натисніть {@examine}" };
    pub const valve1_pass: T = .{ .en = "Pass the valve while it is open", .uk = "Пройдіть клапан, поки він відкритий" };
    pub const neutrophil: T = .{ .en = "Identify a cell rolling on the wall — {@examine}", .uk = "Розпізнайте клітину, що котиться по стінці, — {@examine}" };
    pub const staph: T = .{ .en = "Destroy the bacteria — {0} left", .uk = "Знищте бактерії — ще {0} {0|скупчення|скупчення|скупчень}" };
    pub const tools: T = .{ .en = "Fit DRILL on one arm and SHOOT on the other — {@tool_left} / {@tool_right}", .uk = "Поставте СВЕРДЛО на одну руку, а ПОСТРІЛ на другу — {@tool_left} / {@tool_right}" };
    pub const transit_marker: T = .{ .en = "Fly through the transit marker", .uk = "Пролетіть крізь транзитний маркер" };
    pub const transit: T = .{ .en = "Transit", .uk = "Транзит" };
    pub const v2_approach: T = .{ .en = "Enter the pocket behind the pinned cusp", .uk = "Увійдіть у кишеню за затиснутою стулкою" };
    pub const treat: T = .{
        .en = "Colonies {0}/3 destroyed  ·  Cables {1}/4 cut  ·  Fragments loose {2}",
        .uk = "Знищено колоній: {0}/3  ·  Перерізано тяжів: {1}/4  ·  Вільних уламків: {2}",
    };
    pub const lyse_core: T = .{ .en = "Dissolve the thrombus before it leaves the pocket", .uk = "Розчиніть тромб, доки він не вийшов із кишені" };
    pub const freed: T = .{ .en = "Valve restored", .uk = "Клапан відновлено" };
    pub const to_ring2: T = .{
        .en = "Fly through the transit marker — try a Sync Strike on the way",
        .uk = "Пролетіть крізь транзитний маркер — дорогою спробуйте синхроудар",
    };
    pub const septum_find: T = .{ .en = "Find what is blocking the vein and identify it — {@examine}", .uk = "Знайдіть і розпізнайте те, що перекриває вену, — {@examine}" };
    pub const septum_break: T = .{ .en = "Shatter the phlebolith with Sync punches — {0}%", .uk = "Розбийте флеболіт синхроударами — {0}%" };
    pub const exit: T = .{ .en = "Ride the flow into the femoral vein", .uk = "Пливіть за течією до стегнової вени" };
    pub const done: T = .{ .en = "Chapter complete", .uk = "Розділ завершено" };
    pub const g_arrive: T = .{ .en = "Arrival — proximal jejunum", .uk = "Прибуття — проксимальний відділ порожньої кишки" };
    pub const g_villus: T = .{ .en = "Identify a villus — aim at one and press {@examine}", .uk = "Розпізнайте ворсинку — наведіть приціл і натисніть {@examine}" };
    pub const g_descend: T = .{ .en = "Descend to the crypt floor, out of the stream", .uk = "Спустіться на дно, до крипт, подалі від течії" };
    pub const g_wave: T = .{ .en = "Stay below the villus tips until the ring has passed", .uk = "Залишайтеся нижче від верхівок ворсинок, доки кільце не пройде" };
    pub const g_scan: T = .{ .en = "Scan the villus tips at the marker — {@examine}", .uk = "Проскануйте верхівки ворсинок біля маркера — {@examine}" };
    pub const g_extrude: T = .{
        .en = "Infected cells cleared {0}/{1}  ·  Virus spread {2}  ·  Loose {3}",
        .uk = "Видалено заражених клітин: {0}/{1}  ·  Випадків поширення: {2}  ·  На волі: {3}",
    };
    pub const g_factory: T = .{ .en = "Drill the dome open and fire into it — {0}%", .uk = "Розсвердліть купол і стріляйте всередину — {0}%" };
    pub const g_factory_done: T = .{ .en = "Dome destroyed", .uk = "Купол знищено" };
    pub const g_tether: T = .{
        .en = "Tether to a villus — aim within 0.4 mm and press {@tether}",
        .uk = "Причепіться тросом до ворсинки — наведіть приціл із відстані до 0,4 мм і натисніть {@tether}",
    };
    pub const g_flume: T = .{ .en = "Cross the blunted stretch upstream on the tether", .uk = "Подолайте ділянку сплощених ворсинок проти течії на тросі" };
    pub const s_arrive: T = .{ .en = "Arrival — gastric antrum", .uk = "Прибуття — антральний відділ шлунка" };
    pub const s_pits: T = .{ .en = "Identify a gastric pit — aim at one and press {@examine}", .uk = "Розпізнайте шлункову ямку — наведіть приціл і натисніть {@examine}" };
    pub const s_gradient: T = .{ .en = "Climb until the pH is below 4 — pH {0}", .uk = "Підіймайтеся, доки pH не стане нижчим за 4 — pH {0}" };
    pub const s_gradient_back: T = .{ .en = "Back down into neutral gel — pH {0}", .uk = "Назад у нейтральний гель — pH {0}" };
    pub const s_wave: T = .{ .en = "Shelter inside a gastric pit until the wave has passed", .uk = "Сховайтеся в шлунковій ямці, доки хвиля не пройде" };
    pub const s_swim: T = .{ .en = "Helicobacter in the gel: {0} — strike when one flares", .uk = "Гелікобактер у гелі: {0} — бийте, коли спалахне" };
    pub const s_margin: T = .{ .en = "Colonised pits cleared {0}/{1}  ·  Swimmers {2}", .uk = "Очищено колонізованих ямок: {0}/{1}  ·  Плавців: {2}" };
    pub const s_cross: T = .{ .en = "Cross the crater to the bleeding vessel", .uk = "Перелетіть кратер до судини, що кровить" };
    pub const s_cautery: T = .{ .en = "Press with PUNCH and weld with DRILL together — sealed {0}%", .uk = "Притискайте УДАРОМ і зварюйте СВЕРДЛОМ одночасно — заварено {0}%" };
};
