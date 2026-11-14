# Dentro del cuerpo — design

First-person 3D game. The player is a doctor piloting a cell-sized drone from a vein in the patient's right leg to the brain, treating local disease on the way. World unit = 1 µm. Anatomy is real; drone capabilities and treatment mechanics are fiction and are labelled as such in the in-game atlas.

## Patient and stakes

58-year-old with a colloid cyst of the third ventricle that intermittently plugs the foramina of Monro (obstructive hydrocephalus). Open surgery is ruled out by sepsis from an infected leg thrombus and several comorbidities. The drone goes in through the leg because that is where the infection source is; every later stop removes a problem that would kill the patient before or during the brain operation.

Campaign state carried between chapters: **patient stability** (0–100, mission fails at 0), **embolic load** (clot fragments the player let escape in chapter 1; they lodge in the lungs and set chapter 7's workload), **atlas** (structures and organisms identified), **upgrades**.

## Drone

Hull 8 µm, deformable (red-cell sized, so it passes capillaries). Fictional capabilities, each introduced in the story before a route depends on it:

| Capability | Fiction | Real mechanism it borrows |
|---|---|---|
| Display filter | 99 % of erythrocytes are removed from the pilot's view; blood is opaque otherwise | — |
| Tempo link | pilot perceives 1:100 slowed time; transit sequences drop it to cover centimetres | — |
| Diapedesis frame | squeeze between endothelial cells at venules, fenestrated capillaries, HEVs; never across the blood–brain barrier | leukocyte extravasation |
| Epithelial pass | cross an epithelium only where it is naturally leaky (villus-tip extrusion zone, tonsillar crypt reticulated epithelium, ulcer bed) | cell shedding gaps |
| Mucus tether (ch. 2) | anchor to a surface and crawl against flow | H. pylori / bacterial adhesins |
| Buffer coat (ch. 3) | a bicarbonate reserve the hull spends in acid in place of itself; 12 s, refilled in neutral gel or blood | bicarbonate secreted into the mucus by the surface epithelium |
| Cautery bit (ch. 3) | the drill bit heats as it turns and welds a vessel that the other arm presses flat | coaptive thermal coagulation of a bleeding ulcer vessel |
| Surfactant skin (ch. 7) | cross air–liquid interfaces | pulmonary surfactant |
| Sheath glide (ch. 10) | travel the perineural space of olfactory fila | the route *Naegleria fowleri* takes |

### Arms

Two arms, independently controlled, each fitted with one of three tools at a time. Different tools can run at once.

| Tool | Purpose | Cost / risk |
|---|---|---|
| Punch | Impulse. Shatters brittle material (calcification, stones), knocks back and kills small organisms in a short cone, shoves cells aside harmlessly | Short reach, cooldown. Splits soft clot into two emboli. Bruises tissue |
| Drill | Sustained contact. Cuts fibrous material (fibrin, plaque cap, biofilm matrix). Progress decays if contact breaks | Pins the drone in place; heat. Shreds healthy tissue fast |
| Shoot | Lytic pulse at range. Kills bacteria, dissolves clot fragments | Charge-limited. Strips endothelium on a miss. Absorbed by biofilm slime |

Feedback per arm: the arm is on screen on its own side, its sound is panned to that side, its heat/charge arc sits on that side of the reticle, and hits flash the corresponding half of the crosshair.

Restraint: tissue damage (drill or punch on wall or leaflet, stray shots) and friendly fire on immune cells lower patient stability immediately and the chapter grade afterwards.

## Fellow doctor

Dra. Elena Marín, on comms. State-driven. Inputs: what the reticle rests on (ray cast against entities and analytic anatomy), what the player just did, objective state, time without progress.

- **Identify** (`T`): names the thing under the reticle in one line and files it in the atlas. `T` again on the same thing gives the longer explanation (function, why it matters here, real size).
- **React**: first-time remarks on actions (first wall strike, first friendly fire, first embolus released).
- **Urgent**: at most six words, interrupts anything (“Flare — dodge left!”, “Embolus loose!”).
- **Hint** (`H`, or automatic after a stall): three levels per objective — what to look at, what to do, exactly how.

## Route

Organs sit in parallel on the systemic circuit, the lungs in series with it, the liver in series with the gut. A drone injected into a vein therefore passes the right heart and lungs before it can reach any systemic organ, and passes them again on every later hop. Those passes are transit sequences (tempo link dropped, 4–8 s), not levels; Marín uses them to foreshadow. The heart and lungs become levels only at chapters 7 and 8, when their own problems are next in the triage order.

| # | From → to | Path | Compartments |
|---|---|---|---|
| 0 | Cannula → Vein | 22G cannula (0.41 mm bore) into the right great saphenous vein, distal thigh | saline → venous blood |
| 1→2 | Vein → Intestines | saphenofemoral junction → femoral → external/common iliac → IVC → right heart → pulmonary capillaries → left heart → aorta → superior mesenteric a. → jejunal arcades → vasa recta → villus capillary; diapedesis into lamina propria; epithelial pass at the villus-tip extrusion zone | venous → arterial blood → interstitium → gut lumen |
| 2→3 | Intestines → Stomach | lumen, retrograde on the mucus tether: proximal jejunum → duodenojejunal flexure → duodenum (past the major papilla) → pylorus on a duodenogastric reflux wave → antrum | gut lumen / mucus layer |
| 3→4 | Stomach → Kidneys | exposed venule in the treated ulcer bed → gastric vein → portal vein → liver sinusoids (transit) → hepatic veins → IVC → heart/lungs → aorta → right renal a. → afferent arteriole → glomerulus (filter passes < 8 nm: dead end) → efferent arteriole → vasa recta; diapedesis; cross a collecting duct wall near the papilla → duct of Bellini → minor calyx | blood → interstitium → urinary space |
| 4→5 | Kidneys → Gallbladder | calyceal fornix → venous vasa recta → renal vein → IVC → heart/lungs → aorta → celiac trunk → hepatic a. → cystic a. → wall capillaries; diapedesis + epithelial pass | blood → bile |
| 5→6 | Gallbladder → Liver | bile, retrograde: neck → cystic duct (spiral valve of Heister) → hepatic ducts → interlobular duct at a portal triad; canaliculi are 1 µm, so cross into the neighbouring portal venule → sinusoid | bile → portal blood |
| 6→7 | Liver → Lungs | central vein → hepatic veins → IVC → right heart → pulmonary arteries → alveolar capillaries; later across the 0.5 µm blood–air barrier | venous blood → airspace |
| 7→8 | Lungs → Heart | pulmonary veins → left atrium → mitral valve → left ventricle → aortic root → left coronary ostium (fills in diastole) → LAD | arterial blood |
| 8→9 | Heart → Lymph nodes | back to the aortic root in systole (coronary flow stalls) → arch → right common carotid → external carotid → nodal arteriole → high endothelial venule of the jugulodigastric node; diapedesis (the lymphocyte route) | blood → lymphoid tissue |
| 9→10 | Lymph nodes → Pharynx | subcapsular sinus → afferent lymphatic, retrograde through its bicuspid valves → palatine tonsil → reticulated crypt epithelium → crypt → oropharynx | lymph → mucosal surface |
| 10→11 | Pharynx → Brain | oropharynx → nasopharynx → choana → olfactory cleft → perineural sheath of an olfactory filum → cribriform plate → subarachnoid space → along the olfactory tract to the lamina terminalis cistern → micro-fenestration of the lamina terminalis → third ventricle | air/mucus → perineural → CSF |

Why not the carotid straight to the brain: the blood–brain barrier is the one endothelium the diapedesis frame cannot open, and the lamina terminalis corridor is the one neurosurgeons already use.

## Chapters

| # | Chapter | Feature the player learns to read | Objective | Location-specific challenge | Upgrade / carry-over |
|---|---|---|---|---|---|
| 1 | Vein (R great saphenous) | Venous valve: sinus bulge announces it, leaflet position shows flow direction, pocket behind a cusp is stagnant | Free a cusp pinned by a septic microthrombus: kill the *S. aureus* nests, drill the fibrin anchors, lyse the fragments | Parabolic flow (fast core, still wall) plus calf-pump surges; holding station while drilling | **Sync Servo** (both arms on one beat = Sync Strike). Escaped emboli → ch. 7 |
| 2 | Intestines (jejunum) | Villi and crypts; the contraction ring of a peristaltic wave and the direction it travels | Clear rotavirus-infected villus tips while sparing healthy enterocytes and commensal bacteria | Lumen closes behind every wave; shelter in crypts; chyme opacity; friend/foe only resolves on scan | **Mucus Tether** (anchor, crawl upstream) |
| 3 | Stomach (antrum) | Gastric pits and the mucus pH gradient: safe at the epithelium, pH 2 in the lumen | Clear *H. pylori* from an ulcer margin, cauterise the bleeding vessel | Acid erodes the hull outside the mucus; antral grinding waves; corkscrew bacteria that outrun shots in mucus | **Buffer Coat** (timed acid immunity), drill cautery. Ulcer venule is the exit |
| 4 | Kidneys (R) | Pyramid and papilla: ducts converge on the area cribrosa; the glomerulus as a filter that the drone cannot pass | Break a calcium-oxalate stone off its Randall's plaque into fragments small enough for the ureter | Razor crystal shards; urine jets from the ducts of Bellini; fragment-size discipline | **Resonance** (Sync punch becomes a ranged shockwave) |
| 5 | Gallbladder | Bile layering (sludge under clear bile), mucosal folds, the spiral valve at the neck | Free a cholesterol stone impacted in Hartmann's pouch; punch and drill fail on wax, bile salts do not | CCK contraction crushes everything toward the neck; viscous bile; near darkness | **Emulsifier rounds** (dissolve lipid) |
| 6 | Liver | The hexagonal lobule: triads at the corners, central vein in the middle, flow always triad → centre | Open sinusoids choked by fat-ballooned hepatocytes; clear a portal-borne abscess | Single-file sinusoid maze; Kupffer cells attack an unmarked drone and help a careful one | **Opsonin Tag** (mark targets for immune cells) |
| 7 | Lungs | The alveolus through a breath: capillary mesh, 0.5 µm barrier, surfactant film | Lyse the emboli from ch. 1, then drain one consolidated alveolus of pneumococci | Air–liquid interfaces trap the drone; everything expands and collapses on the breath | **Surfactant Skin** |
| 8 | Heart (left) | The cardiac cycle read from valve states; coronaries fill in diastole | Strip an endocarditis vegetation from the mitral leaflet; debulk an LAD atheroma without rupturing its cap | Violent pulsatile flow; chordae; all windows are one beat long | **Beat Lock** (dash and steady aim phase-locked to the pulse) |
| 9 | Lymph nodes (jugulodigastric) | Node architecture: sinus, follicles, paracortex, medulla, and who lives where | Find infected B cells among healthy lymphocytes and present antigen to dendritic cells so the node does the killing | Crowded tissue where nearly everything is friendly and retaliates if harmed | **Antigen Library** (call T-cell support) |
| 10 | Pharynx | Mucociliary escalator: metachronal waves point toward the throat; the swallow wave | Break up a streptococcal biofilm and tonsilloliths, climb against the cilia to the olfactory cleft | A swallow sweeps the unanchored drone into the oesophagus; coughs; air–mucus films | **Sheath Glide** |
| 11 | Brain (third ventricle) | CSF pulsation and flow from the choroid plexus through the foramina; fornix and veins that must not be touched | The operation (below) | Millimetre margins beside structures that hold memory | — |

### Final operation

Each phase is one earlier lesson under tighter margins: (1) fenestrate the lamina terminalis with Sync drill strikes timed to the CSF pulse (ch. 1 sync, ch. 8 beat); (2) read the flow to find the plugged foramen (ch. 1 valves, ch. 6 flow-following); (3) crack the cyst's calcified cap by resonance (ch. 4); (4) emulsify and drain the viscous colloid (ch. 5) while the tether holds station (ch. 2); (5) drill the cyst pedicle off the choroid plexus and cauterise (ch. 3) with opportunistic organisms tagged for microglia rather than shot beside the fornix (ch. 6, ch. 9); (6) ride the restored CSF surge out through the aqueduct (ch. 7, ch. 10 timing).

## Hidden chapters

| Chapter | How it is found | Route |
|---|---|---|
| Bone marrow (R femur) | Ch. 1: three cells in the stream look wrong (reticulocytes, band neutrophils). Identifying all three makes Marín ask where they are coming from and logs the route | femoral vein → profunda → nutrient vein of the femur → marrow sinusoids. Megakaryocytes shedding platelets; teaches cell lineage, pays out an atlas bonus that speeds scans |
| Inner ear (R cochlea) | Ch. 10: an opening on the nasopharynx wall exists only while the patient swallows (the pharyngotympanic tube). Wait at the torus tubarius through one swallow | Eustachian tube → middle ear (ossicles as architecture) → round window → scala tympani. Sound drives the level; pays out a navigation upgrade (pressure-wave sensing) |

## Chapter 1 beat sheet (first playable)

Stations are 1–2 cm of a 3.6 mm vein; two time-compressed transits stand in for the ~30 cm between them.

1. **Injection.** Start inside the cannula bore. Saline flush pushes the drone out of the bevel. Comms check, look, thrust.
2. **Flow.** Marín has the player compare the core with the wall layer. Free flight to the first valve.
3. **Valve 1 (healthy).** Sinus bulge, leaflets opening on the pump surge. Pass on an open phase. Checkpoint.
4. **Guide interaction.** A neutrophil rolling on the wall; identify it. First planktonic staph: shoot. Marginating neutrophils thicken toward the infection, which is the cue to follow.
5. **Transit** to the diseased valve.
6. **Valve 2.** One cusp is pinned shut by a microthrombus in its pocket. Enter the pocket from downstream. Three biofilm nests: slime absorbs shots, so one arm drills the matrix open while the other shoots the core (dual-arm requirement). Four fibrin anchors: drill each for ~3 s while shooting the swarms that come for the drone; anchors re-knit while any nest lives. Each anchor that parts releases clot fragments that must be lysed before they leave downstream.
7. **Upgrade.** Cusp freed, stability up, Sync Servo delivered.
8. **Transit** to the saphenofemoral junction.
9. **Exit gate.** A phlebolith (calcified old thrombus) wedged in the terminal valve; only Sync punches fracture it, with a last swarm contesting the timing.
10. **End.** Into the femoral vein. Debrief with grade, embolic load, atlas count. Retry from checkpoint on hull loss; chapter restart on patient loss or from the pause menu.

## Chapter 2 beat sheet (playable)

One 1.2 cm stretch of proximal jejunum between two circular folds: villi 0.65–0.9 mm tall on a 0.3 mm
hexagonal pitch, crypt mouths in the floor between them. The drone arrives at the aboral end and works orad,
against the stream.

1. **Arrival.** Out through a villus tip after the transit. The chyme stream runs at about 0.8 mm/s above the
   tips and is nearly still between the shafts, which repeats the vein's core-and-wall lesson in a new shape.
2. **Contraction.** A ring of circular muscle travels aborad every 38 s and brings the far wall down onto the
   villus tips. The pilot reads its direction and arrival time from the HUD and from the roof, and waits it
   out below the tips; anything above them is crushed.
3. **Scan.** Infected enterocytes look like their neighbours. The identify pulse resolves what is within
   0.7 mm: infected cells, rotavirus particles, and commensal bacteria that must be left alone.
4. **Treatment.** Shooting or drilling an infected cell where it sits ruptures it, which releases virus and
   damages the lining. Punch extrudes it whole, as the villus tip does to its own old cells, and the freed
   cell is then lysed with a shot before it bursts. Loose virions either settle on a clean tip and infect it
   or wind up and dart at the drone.
5. **Viroplasm dome.** A cluster of fused cells sheds virions until one arm drills its membrane open and the
   other fires into the opening (the chapter's dual-arm encounter).
6. **Upgrade.** Mucus Tether: a mucin line to any tissue within 0.4 mm that reels the drone in and holds it
   against the stream.
7. **Blunted stretch.** Two millimetres where the infection has flattened the villi to stubs and the stream
   reaches the floor. It cannot be flown, even on boost, and is crossed one tether pull at a time.
8. **End.** Exit ring toward the duodenum. Debrief with grade, spread count, commensals lost and hits on the
   lining; the same retry paths as chapter 1.

Real: villus and crypt dimensions, enterocyte turnover and tip extrusion, rotavirus villus blunting and
viroplasms, peristaltic rings travelling aborad. Fiction: the scan pulse, the tether, and the pace of all of
it.

## Chapter 3 beat sheet (playable)

A 9 mm strip of antral mucosa running from near the pylorus to a peptic ulcer 6 mm across: gastric pits 70 µm
wide and 0.2 mm deep on a 0.15 mm hexagonal pitch, under 0.3 mm of adherent mucus gel that thins to nothing
at the ulcer's heaped rim. The crater is 0.5 mm deep and bare. The drone arrives in the gel at the pyloric
end and works towards the ulcer.

1. **Arrival.** Set down in the gel after the climb from the jejunum. The HUD gains a pH reading at the hull.
   The pilot identifies a pit.
2. **Gradient.** Marín has the pilot rise through the gel. The reading falls from 7 at the lining to 2 at the
   top of the gel, the colour of the water changes with it, and below pH 4.5 the hull erodes. Back in neutral
   gel the erosion is repaired, which is the rule for the rest of the chapter: acid damage is a debt that
   neutral gel pays off, and only an empty hull is final.
3. **Antral wave.** Every 40 s a ring of contraction travels towards the pylorus and closes the lumen
   completely, the far wall pressed onto this one. The HUD counts it in. Nothing on the surface survives it,
   and the pits stay open, so the pilot tethers down into one and waits.
4. **Swimmers.** *Helicobacter pylori* in the gel: corkscrew rods that outrun a round fired from a distance,
   because the gel slows the round and not them. Before it darts at the drone a swimmer stops and flares for
   most of a second, and that is when a round arrives; a punch at arm's length and a Sync Strike's shockwave
   work at any time.
5. **Margin.** Four pits beside the rim are packed with colonies, which keep their pits neutral with ammonia
   and shed swimmers while the drone is near. Rounds wear a colony down, the drill does too, and both arms
   on one colony clear it fastest. The gel here is too thin to protect the surface between pits, so the pilot
   crosses low and quickly and rests inside the pits, cleared ones included.
6. **Upgrade.** Buffer Coat and the cautery bit, with the margin clear.
7. **Crater.** Over the rim into pH 2 with the coat counting down, to an arteriole in the bed with one wall
   eaten through. The blood around it is neutral and refills the coat. The pilot fixes a tether to the bed,
   because each wave now squirts juice back through the crater, then presses the vessel flat with a punch
   and welds it with the drill while it is flat: six seconds of drilling, all of it with the other arm
   pressing (the chapter's dual-arm encounter). Until it is sealed the vessel bleeds and stability falls.
8. **End.** Out through a venule that the crater has laid open, towards the portal vein. Debrief with grade,
   colonies cleared, seconds the vessel bled, seconds of acid on a bare hull and hits on the lining; the
   same retry paths as chapters 1 and 2.

Real: pit dimensions and spacing, the thickness of the gel and the pH gradient across it, bicarbonate
secretion by the surface cells, *H. pylori*'s size, helical shape, motility in mucus and urease-made ammonia,
its colonisation of antral pits, retropulsion of gastric contents by the antral wave, and coaptive
coagulation as the treatment for a bleeding ulcer vessel. Fiction: the coat, a drill that welds, a hull that
gel repairs, a wave every 40 s instead of every 20, and the pace of all of it.
