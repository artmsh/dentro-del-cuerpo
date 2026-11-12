//! Dra. Elena Marín: the atlas of things she can identify, and the queue that turns game events into
//! subtitles. State-driven; no generation at runtime.

const std = @import("std");

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
    name: []const u8,
    size: []const u8,
    /// One line, said on first identification.
    short: []const u8,
    /// Said when the pilot asks again.
    deep: []const u8,
    hostile: bool = false,
};

pub fn entry(t: Topic) Entry {
    return switch (t) {
        .red_cell => .{
            .name = "Erythrocyte",
            .size = "7.8 µm",
            .short = "Erythrocyte — a red blood cell. 7.8 microns: about your size.",
            .deep = "No nucleus, just haemoglobin in a dimpled disc. The dimple adds surface for gas exchange and lets the cell fold through capillaries narrower than itself. There are five million in every microlitre; your display hides ninety-nine in a hundred or you would see nothing else. These are dark because venous blood has already given up its oxygen.",
        },
        .platelet => .{
            .name = "Platelet",
            .size = "2–3 µm",
            .short = "Platelet. A cell fragment that plugs breaks in the vessel wall.",
            .deep = "Shed by megakaryocytes in the bone marrow. Where endothelium is injured they stick, change shape and call in fibrin. That is why every stray round into the wall costs the patient: you start the clotting we came to remove.",
        },
        .vein_wall => .{
            .name = "Endothelium",
            .size = "wall 3.6 mm across",
            .short = "Endothelium. The vein's lining, one cell thick.",
            .deep = "Each cobble is one endothelial cell, stretched along the flow. Intact endothelium is the one surface in the body that blood will not clot on; scrape it and platelets arrive in seconds. This vein is 3.6 millimetres across — four hundred and fifty of your hulls.",
        },
        .cannula => .{
            .name = "Cannula",
            .size = "22 G, bore 0.41 mm",
            .short = "Our cannula. 22 gauge. That is how you got in.",
            .deep = "A steel tube ground to a long bevel so it parts the vein wall instead of coring it. To you it is a tunnel fifty hulls wide. I am holding the other end; there is nothing for you back up there.",
        },
        .leaflet => .{
            .name = "Valve cusp",
            .size = "cusp ~2 mm long",
            .short = "Valve cusp. It lets blood climb the leg and stops it falling back.",
            .deep = "Leg veins work against gravity. Calf muscle squeezes blood upward; when the muscle relaxes the blood tries to fall, fills the pockets behind the two cusps and presses them shut. Read the cusps and you have read the flow: against the wall means forward flow, meeting in the middle means reflux.",
        },
        .sinus => .{
            .name = "Valve sinus",
            .size = "bulge +30 %",
            .short = "Valve sinus. The wall bulges to make room for the pocket behind a cusp.",
            .deep = "The bulge is how you spot a valve from a distance. Behind the cusp the blood barely moves; it turns in a slow vortex. Stagnant blood is where a thrombus starts, which is why deep-vein clots begin in valve pockets.",
        },
        .neutrophil => .{
            .name = "Neutrophil",
            .size = "12 µm",
            .short = "Neutrophil. White cell, first responder to bacteria. On our side.",
            .deep = "They leave the fast core and roll along the wall on selectin bonds, waiting for the signal to squeeze through into tissue. That is margination, and the squeeze is the trick your diapedesis frame copies. More rolling cells means inflammation close by: follow where they thicken.",
        },
        .staph => .{
            .name = "Staphylococcus aureus",
            .size = "cocci 1 µm, cluster ~5 µm",
            .short = "Staphylococcus aureus. Cocci in clusters. Hostile.",
            .deep = "Staphyle is Greek for a bunch of grapes. It secretes coagulase, which turns the patient's own fibrinogen into a fibrin coat: it builds clots to hide in. On your display a cluster glows gold before it lunges; that glow is your cue. The lunge is our threat model — real cocci only drift.",
            .hostile = true,
        },
        .nest => .{
            .name = "Biofilm colony",
            .size = "dome ~90 µm",
            .short = "Biofilm. A colony under a slime of sugars and fibrin.",
            .deep = "The matrix soaks up antibiotics and our lytic rounds alike. The only way in is mechanical: hold the drill in the slime to open it, and put rounds through the opening with your other arm before it closes again.",
            .hostile = true,
        },
        .anchor => .{
            .name = "Fibrin cable",
            .size = "~0.5 mm long",
            .short = "Fibrin cable. Clot protein tying the thrombus down.",
            .deep = "Fibrin is the mesh in every clot. Fresh fibrin dissolves; cross-linked, and here re-knit by coagulase, it has to be cut. The drill cuts it. While any colony lives, it re-knits what you cut.",
        },
        .thrombus => .{
            .name = "Thrombus",
            .size = "0.7 mm",
            .short = "Thrombus. Red cells and platelets in a fibrin mesh, lodged in the valve pocket.",
            .deep = "Too small for the ultrasound to have caught, large enough to pin the cusp. Do not punch or drill the body: what breaks off travels to the lungs. Cut it loose first, then dissolve it.",
        },
        .embolus => .{
            .name = "Embolus",
            .size = "20–30 µm",
            .short = "Embolus — a piece of clot loose in the flow.",
            .deep = "It rides the vena cava to the right heart and lodges in the first lung artery narrower than itself. Lytic rounds dissolve it. A punch only makes two.",
            .hostile = true,
        },
        .septum => .{
            .name = "Post-thrombotic web",
            .size = "spans the lumen",
            .short = "Post-thrombotic web. Scar from an old clot, grown across the vein.",
            .deep = "A thrombus the body cannot clear is organised into fibrous tissue. This one left a single channel. It is why this leg has been swelling for years.",
        },
        .phlebolith => .{
            .name = "Phlebolith",
            .size = "0.38 mm",
            .short = "Phlebolith. A vein stone: old thrombus turned to calcium.",
            .deep = "Calcium phosphate — hard and brittle. Rounds do nothing and the drill skates. It breaks on impact, and only when both arms land together.",
        },
        .transit => .{
            .name = "Transit marker",
            .size = "display overlay",
            .short = "Transit marker. Mine. Fly through it and I take the flow from there.",
            .deep = "Between stations I drop your tempo link from one-in-a-hundred to real time and let the blood carry you. Three seconds for you is twelve centimetres of vein.",
        },
        .reticulocyte => .{
            .name = "Reticulocyte",
            .size = "8.5 µm",
            .short = "Odd. A reticulocyte — a red cell one day out of the marrow, still carrying RNA.",
            .deep = "Normally one red cell in a hundred. The mottling is leftover ribosomes; it will be gone in a day. Seeing them easily means the marrow is pushing cells out early.",
        },
        .band_cell => .{
            .name = "Band neutrophil",
            .size = "13 µm",
            .short = "Band neutrophil. Immature: the nucleus is still a horseshoe. Released early.",
            .deep = "A mature neutrophil's nucleus has three to five lobes. Bands in the blood are a left shift: the marrow emptying its reserve because the infection is using neutrophils faster than they mature.",
        },
        .nucleated_red_cell => .{
            .name = "Nucleated red cell",
            .size = "9 µm",
            .short = "A red cell with its nucleus still in it. That should never be out here.",
            .deep = "Erythroblasts eject their nucleus before they leave the marrow. One in the circulation of an adult means the marrow is under severe stress.",
        },
        .villus => .{
            .name = "Villus",
            .size = "0.8 mm tall",
            .short = "A villus. One finger of the gut lining; everything she eats is absorbed through these.",
            .deep = "Each cobble is an enterocyte, and each enterocyte carries three thousand microvilli of its own: fold on fold, the small intestine reaches the area of a studio flat. Inside the finger are a capillary loop for sugars and amino acids and one blind lymph vessel, the lacteal, for fat. You came up that capillary.",
        },
        .villus_tip => .{
            .name = "Villus tip",
            .size = "extrusion zone",
            .short = "The tip. Cells are born in the crypts, climb for four days and are pushed out here.",
            .deep = "The lining replaces itself every four to five days. At the tip a worn-out cell is squeezed out by its neighbours, which close the gap underneath it before it leaves, so the barrier never opens. Rotavirus infects exactly these mature cells. If you push an infected one out the way the gut would, the sheet seals behind it.",
        },
        .crypt => .{
            .name = "Crypt mouths",
            .size = "pits 50 µm apart",
            .short = "Crypts of Lieberkühn. Stem cells sit at the bottom of each pit; this floor is the nursery.",
            .deep = "A crypt makes about three hundred cells a day and sends them up the neighbouring villi. Nothing digests down here and almost nothing flows, which makes it the one place a contraction ring cannot reach you. Do not fire into it: the stem cells are what will rebuild whatever the virus strips.",
        },
        .blunted_villus => .{
            .name = "Blunted villus",
            .size = "0.15 mm stub",
            .short = "That was a villus. The virus killed the tip cells faster than the crypts could replace them.",
            .deep = "Villus blunting. With the absorbing cells gone, sugar stays in the lumen and drags water after it, and the viral toxin NSP4 makes the crypts secrete on top of that. This stretch is why she has lost three litres since yesterday. It grows back within a week once the virus is cleared.",
        },
        .contraction => .{
            .name = "Contraction ring",
            .size = "travels at 1–2 cm/s",
            .short = "That is the opposite wall coming down. A peristaltic ring: the gut is squeezing shut around you.",
            .deep = "Circular muscle contracts behind the contents and relaxes ahead of them, so the ring always travels away from the mouth. It closes the lumen down to the villus tips; the villi mesh like the bristles of two brushes and the spaces between them stay open. The ring cannot hurt you between the villi. On top of one it can.",
            .hostile = true,
        },
        .lipid_droplet => .{
            .name = "Fat droplet",
            .size = "1–10 µm",
            .short = "Emulsified fat. Bile salts have broken her breakfast into droplets.",
            .deep = "Pancreatic lipase works on the surface of these, shaving them into fatty acids that travel in micelles two hundred times smaller. The bile that made this emulsion was stored in the gallbladder; we will see where it comes from.",
        },
        .unknown_microbe => .{
            .name = "Unresolved",
            .size = "under 5 µm",
            .short = "Too small to call from its outline. Scan before you shoot: most of what lives here is on her side.",
            .deep = "There are more bacteria in her gut than cells in her body, and nearly all of them are working for her. At this size a virus-laden bleb and a commensal rod look the same until the scan reads their surface.",
        },
        .infected_cell => .{
            .name = "Infected enterocyte",
            .size = "swollen, 18 µm",
            .short = "Infected enterocyte: swollen, full of virus. Punch it out of the sheet. Do not burst it where it sits.",
            .deep = "The virus has turned the cell into a replication site; rupture it in place and thousands of particles land on its neighbours. A firm push from the lumen side makes the neighbours do what they do at the tip anyway: squeeze it out and seal the gap. Once it is free in the lumen, destroy it before it bursts on its own.",
            .hostile = true,
        },
        .shed_cell => .{
            .name = "Shed infected cell",
            .size = "16 µm",
            .short = "That one is out. It will burst in a few seconds. Shoot it first.",
            .deep = "A dying infected cell releases its virus by lysis. Your rounds carry a protease load that destroys the particles along with the cell; left alone it scatters them over the nearest villi.",
            .hostile = true,
        },
        .rotavirus => .{
            .name = "Rotavirus bleb",
            .size = "3 µm cluster of 70 nm particles",
            .short = "Rotavirus, travelling in a membrane bleb. It is looking for a healthy tip. One round.",
            .deep = "Single particles are seventy nanometres, far below your optics; what you see is a vesicle packed with them, which is how the virus really spreads between cells. Each wheel-shaped particle carries eleven segments of double-stranded RNA. A bleb that reaches a mature enterocyte infects it, and you will not see that cell again until you scan.",
            .hostile = true,
        },
        .commensal => .{
            .name = "Commensal bacteria",
            .size = "2–4 µm rods",
            .short = "Commensals. Hers. Leave them alone.",
            .deep = "Bacteroides and lactobacilli. They ferment what she cannot digest, make vitamin K, train her immune system and occupy the surfaces a pathogen would need. Every one you kill is ground handed to the next infection.",
        },
        .viral_factory => .{
            .name = "Viroplasm dome",
            .size = "0.12 mm",
            .short = "A whole tip fused into one infected mass, capped in mucus. Rounds will not get through the cap.",
            .deep = "Viroplasms are the factories the virus builds inside a cell. Here neighbouring cells have fused around them and the goblet cells have buried the lot in mucus. Drill the cap open and fire into the breach while it is open; it will shed blebs at you the whole time.",
            .hostile = true,
        },
    };
}

pub const Priority = enum(u8) { chatter, normal, urgent };

const Pending = struct { text: []const u8, prio: Priority };

/// Subtitle queue. Urgent lines interrupt; chatter is dropped when she is already talking.
pub const Voice = struct {
    current: ?[]const u8 = null,
    urgent: bool = false,
    remaining: f32 = 0,
    age: f32 = 0,
    queue: [12]Pending = undefined,
    len: usize = 0,
    /// Incremented whenever a new line starts (the audio layer plays a comm chirp on change).
    serial: u32 = 0,

    pub fn say(v: *Voice, text: []const u8, prio: Priority) void {
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

    fn start(v: *Voice, text: []const u8, urgent: bool) void {
        v.current = text;
        v.urgent = urgent;
        v.age = 0;
        v.remaining = holdTime(text, urgent);
        v.serial +%= 1;
    }

    pub fn holdTime(text: []const u8, urgent: bool) f32 {
        const base: f32 = if (urgent) 1.6 else 2.2;
        return base + @as(f32, @floatFromInt(text.len)) * 0.052;
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

test "a stage change drops the lines queued for the old objective" {
    var v: Voice = .{};
    v.say("a long instruction for the old objective, still on screen", .normal);
    v.say("stale follow-up", .normal);
    v.supersede();
    v.say("new objective", .normal);
    try std.testing.expect(v.remaining <= 1.3);
    v.update(1.4);
    try std.testing.expectEqualStrings("new objective", v.current.?);
}

test "urgent interrupts and chatter is dropped while talking" {
    var v: Voice = .{};
    v.say("first", .normal);
    v.say("second", .normal);
    v.say("idle remark", .chatter);
    try std.testing.expectEqualStrings("first", v.current.?);
    v.say("Dodge!", .urgent);
    try std.testing.expectEqualStrings("Dodge!", v.current.?);
    v.update(30);
    try std.testing.expectEqualStrings("second", v.current.?);
    v.update(30);
    try std.testing.expect(v.current == null);
}

test "every topic has an entry with a short and a deep line" {
    for (0..Topic.count) |i| {
        const e = entry(@enumFromInt(i));
        try std.testing.expect(e.name.len > 0 and e.short.len > 0 and e.deep.len > e.short.len);
    }
}
