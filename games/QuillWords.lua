-------------------------------------------------------------------------------
-- Campfire Games: Quill word lists
--
-- answers: everyday five-letter words a puzzle can pick from.
-- extra: other five-letter words that count as valid guesses.
-------------------------------------------------------------------------------

local _, ns = ...

local function Split(s)
  local t = {}
  for w in s:gmatch("%a+") do t[#t + 1] = w end
  return t
end

local ANSWERS = [[
about above actor acute adapt admit adopt adult after again agent agree ahead alarm album alert
alike alive allow alone along alter among ample angel anger angle angry ankle apart apple apply
apron arena argue arise armor aroma arrow aside asset atlas attic audio avoid awake award aware
awful baker bacon badge basic basil basin basis batch beach beard beast begin being bench berry
birth black blade blame blank blast blaze bleak blend bless blind block blond bloom blown board
boast boost booth bound brain brake brand brave bread break breed brick bride brief bring brisk
broad broke brook broom brown brush build built bunch burst buyer cabin cable camel candy canoe
cargo carry carve catch cause cedar chain chair chalk charm chart chase cheap check cheek cheer
chess chest chief child chill chime chunk cider cigar civic claim clash class clean clear clerk
click cliff climb cling cloak clock close cloth cloud clown coach coast cocoa color comet comic
coral couch cough could count court cover crack craft crane crash crate crawl crazy cream creek
creep crest crisp cross crowd crown crumb crush crust cubic curly curve cycle daily dairy daisy
dance dated dealt death debut decay delay delta dense depth derby diary dirty ditch dizzy dodge
doing donor doubt dough dozen draft drain drama drank drape drawn dream dress dried drift drill
drink drive drown dryer duchy dusty dwarf dwell eager eagle early earth easel eaten eight elbow
elder elect elite email ember empty enact enemy enjoy enter entry equal equip erase error essay
event every exact exist extra fable faint fairy faith false fancy fatal fault feast fence ferry
fever fiber field fifth fifty fight final finch first flame flash flask fleet flesh flint float
flock flood floor flour fluid flute focus foggy force forge forth forty forum found frame frank
fresh friar front frost fruit fully funny gamer gavel genre ghost giant given giver glade glass
gleam glide globe gloom glory glove glued going grace grade grain grand grant grape graph grasp
grass grave gravy great greed green greet grief grill grind groan groom gross group grove grown
guard guess guest guide guild guilt habit handy happy harsh haste hasty hatch haunt haven hazel
heart heavy hedge hello hence heron hinge hobby holly honey honor horse hotel house hover human
humid humor hurry icing ideal image imply index inner input irony issue ivory jazzy jelly jewel
joint jolly joker judge juice juicy jumbo kayak kebab khaki kitty knack kneel knelt knife knock
knoll known label labor lance large laser latch later laugh layer learn lease least leave ledge
legal lemon level lever light lilac limit linen liner lived liver lobby local lodge lofty logic
loose lover lower loyal lucky lunar lunch lyric magic major maker mango maple march marsh mason
match mayor medal media melon mercy merge merit merry metal meter might minor minus mirth mixed
model moist money month moody moose moral motor mount mouse mouth movie muddy mural music naive
nanny nasty naval nerve never newly night noble noise north notch noted novel nurse nutty oasis
occur ocean offer often olive onion opera orbit order organ other otter ought ounce outer owner
oxide paint panel panic paper party pasta paste patch pause peace peach pearl pedal penny perch
peril phase phone photo piano piece pilot pinch pitch pixel pizza place plain plane plant plate
plaza plead pluck plumb plume plush point polar poker porch pouch pound power prank press price
pride prime print prior prize probe proof proud prove prune pupil puppy purse quack quail quake
qualm queen query quest queue quick quiet quilt quirk quote radar radio raise rally ranch range
rapid ratio raven reach react ready realm rebel refer reign relax relay reply rider ridge rifle
right rigid risky rival river roast robin robot rocky rouge rough round route royal rugby ruler
rural sadly safer saint salad salon sandy sauce savor scale scarf scene scent scone scope score
scout scrap screw sedan seize sense serve setup seven shade shady shaft shake shall shame shape
share shark sharp shave shawl sheep sheer sheet shelf shell shift shine shiny shirt shock shore
short shout shown shrub sight silky silly since sixth sixty sized skate skill skirt skull slate
sleep slice slide slope small smart smell smile smoke snack snake sneak solar solid solve sorry
sound south space spare spark speak speed spell spend spice spicy spike spine spoke spoon sport
spray squad stack staff stage stain stair stake stale stamp stand stare stark start state steak
steam steel steep steer stern stick stiff still sting stock stone stood stool store storm story
stove strap straw stray strip stuck study stuff style sugar suite sunny super surge swamp swear
sweat sweep sweet swept swift swing sword table taboo tacit taken tally talon tango taste teach
tease tempo tenth thank theme thick thing think third thorn those three threw throw thumb thyme
tidal tiger tight timer tired title toast today token tonic tooth topic torch total touch tough
towel tower toxic trace track trade trail train trait trash treat trend trial tribe trick
tried troop trout truck truly trunk trust truth tulip tummy tuner twice twist ultra uncle under
unfit union unite unity until upper upset urban usage usual utter vague valid value valve vapor
vault vegan venue verse vigor villa vinyl viola viral visit vital vivid vocal voice voter wagon
waist waltz waste watch water weary weave wedge weigh weird whale wheat wheel where which while
whirl white whole whose widow width wield windy witch woman world worry worth would wound woven
wrist write wrong yacht yearn yeast yield young youth zebra aloud amber acorn adore agile alley
amuse anvil array aisle alpha altar beige bible bingo birch bison blush boxer brace braid bugle
bunny canal cello chore civil clamp clove clump cobra crepe crept deity depot diner dolly donut
drone dusky eerie ethic fauna fetch fiery finer flair flare flora flown foamy forte foyer fudge
furry gaily gecko ghoul glint goose gourd grail gruel gully hairy hefty hippo humus hutch igloo
inept juror kiosk koala lapse larva lasso llama lusty macaw madam manor marry mauve melee mocha
motel mound mover mulch nacho niche ninth noisy nomad nudge oaken olden onset oxbow patio pecan
penne petal piety plank poise polka poppy posse prawn quota ramen rinse rodeo rowdy ruddy rusty
saucy sauna scald scoop seedy shrug siege sieve sloth slump smirk snore soapy sober spade spoil
spree squid stalk stork strut suede swirl tabby taffy tardy tawny tepid thigh tonal topaz torso
twirl udder umber unzip usher valor vowel wharf whisk wispy witty woody yodel zesty
]]

local EXTRA = [[
aback abase abate abbey abbot abhor abide abled abode abort abyss ached aches acids acres acrid
acted actin adage added adder addle adept adieu adios adobe adorn aegis aeons affix afire afoot
afoul agape agate agave aggro aging agony agora aider aides ailed aimed aimer aired alack alder
aleph algae alibi alien align allay allot alloy aloes aloft aloha aloof altos alums amass amaze
ambit amble amend amigo amino amiss amity amour amply angst anime anion anise annex annoy annul
anode antic antsy aorta apace aphid aping apnea aptly arbor ardor areas argon arias armed arose
arson artsy ascot ashen ashes asked asker askew aspen assay aster astir atoll atoms atone audit
auger aught augur aunts aural auras autos avail avers avert avian await awash awoke axial axiom
axles axons azure babel babes backs badly bagel baggy bails baits baize baked bakes balds baldy
baled bales balks balky balls balmy balsa banal bands bandy banes bangs banjo banks banns barbs
bards bared barer bares barge barks barns baron barre basal based baser bases basks basso baste
bated bathe baths baton batty bawdy bawls bayou beads beady beaks beams beans bears beats beaus
beaut bebop becks beech beefs beefy beeps beers beets befit began begat beget begun belay belch
belie belle bells belly below belts bends bento bergs berth beryl beset besot bicep bides bided
bidet bifid bigot bikes bilge bills billy binds binge biome birds bites bitty blahs bland blare
bleat bleed bleep blest blimp blini blink blips bliss blitz bloat blobs blocs bloke blood blots
blows bluer blues bluff blunt blurb blurs blurt boars boats bobby bocks boded bodes bogey boggy
bogus boils bolts bombs bonds boned bones bonus books booms boons boors boots booty booze boozy
borax bored borer bores borne boron bosom bossy botch bough bouts bowed bowel bower bowls boxed
boxen boxes bract brads brash brass brats bravo brawl brawn brays braze breve brews briar bribe
brier brigs brims brine brink briny broil brood broth brows bruin bruit brunt brusk brute bucks
budge buffs buggy bulbs bulge bulgy bulks bulky bulls bully bumps bumpy bunks buoys burly burns
burnt burps burro burrs busby bused buses bushy busty butch butte buxom buzzy bylaw bytes byway
cabal cabby cacao cache cacti caddy cadet cadre cafes caged cages cairn cakes calls calms calyx
cameo camps campy canes canny canon canto caper capes capon carat cards cared carer cares carol
carom carps carte carts cases casks caste casts cater caved caves cavil cease cells cents chafe
chaff champ chant chaos chaps chard chars chasm chats cheat chefs chewy chick chide chili chimp
china chins chips chirp chits chive chock choir choke chomp chops chord chose chuck chugs
chump churn chute cinch circa cited cites civet clack clams clang clank clans claps clasp claws
clays cleat clefs cleft clime clink clips clods clogs clone clots clout cloys clubs cluck clued
clues clung clunk coals coati coats cocky codas coded coder codes coils coins colas colds
colic colon colts comas combs comfy comma conch condo cones coney conga conic conks cooed cooks
cools coops coots coped copes copra cords cored cores corgi corks corky corns corny corps costs
coupe coups coven coves covet covey cowed cower cowls coyly coypu cozen crabs crags cramp crams
crank craps crass crave craws craze creak credo creed creel creme cress crews cribs crick cried
crier cries crime crimp croak crock crone crony crook croon crops croup crows crude cruel cruet
crypt cubed cubes cubit cuffs culls cults cumin cupid curbs curds cured cures curio curls curry
curse curvy cushy cusps cuter cutie cynic cysts czars daffy dales dally dames damns damps dandy
dared dares darks darns darts dater dates datum daubs daunt davit dawns dazed dazes deals deans
dears deary debar debit debts debug decaf decal decks decor decoy decry deeds deems deeps deers
defer deice deify deign deist delis dells delve demon demos demur denim dents desks deter detox
deuce devil dhows diced dices dicey dicta diets digit dikes dills dimes dimly dined dines dingo
dingy dinks dinos diode dippy direr dirge disco discs dishy disks ditto ditty divan divas dived
diver dives divot docks dodgy dodos doers doffs dogma doily dolls dolts domed domes dooms doors
dopey doped dopes dorks dorky dorms doses dotty douse doves dowdy dowel downs downy dowry dowse
dozed dozes drabs drags drake drawl draws drays dread dregs dribs drier dries drips droll drool
droop drops dross drove drubs drugs drums drunk dryad dryly duals ducal ducks ducts duels duets
duffs dukes dulls dully dummy dumps dunce dunes dunks duped dupes dusks dusts dutch duvet
dwelt dyers dying eared earls earns eased eases eater eaves ebbed ebony eclat edema edged edger
edges edict edify edits egged egret eider eject eking elate elegy elfin elide elope elude elves
embed emcee emend emits emote ended ender endow enema ennui ensue envoy epics epoch epoxy erect
erode erred erupt ester ethos ethyl etude evade evens evict evils evoke exalt exams excel exert
exile exits exons expat expel expos extol exude exult eyers eying faced faces facet facts faded
fades fails fairs faked faker fakes falls famed fangs farce fared fares farms fated fates
fauns favor fawns fazed fazes fears feats fecal feces feeds feels feign feint fella felon
felts femur fends feral ferns ferny fetal fetid fetus feuds fewer fiats fibre fiche fiend fifes
filed files filet fills filly films filmy filth finds fined fines finis fired fires firms firth
fishy fists fiver fives fixed fixer fixes fizzy fjord flack flags flail flake flaky flank flans
flaps flats flaws flays fleas fleck flick flied flier flies fling flips flirt flits floes flops
floss flout flows flubs flues fluff fluke fluky flume flung flunk flush flyer foals foams focal
foils foist folds folio folks folly fonts foods fools foots foray fords fores forgo forks forms
forts fossa fouls fount fours fowls foxed foxes frail franc frats fraud frays freak freed freer
frees frets fried fries frill frisk frizz frock frogs frond froth frown froze frump fryer fuels
fugue fumed fumes funds fungi funky furls furor furze fused fuses fussy fusty futon fuzzy gabby
gable gaffe gains gaits galas gales galls gamed games gamey gamma gamut gangs gaols gaped gapes
garbs gases gasps gassy gated gates gator gaudy gauge gaunt gauze gawks gawky gayer gazed gazer
gazes gears geeks geeky geese gelds gelid genie gents genus geode germs getup gibes giddy gifts
gilds gills gilts gimps girds girls girly girth gismo gives gizmo glads gland glare glaze glean
glens glitz gloat globs gloss glows glues gluey glums gluts glyph gnarl gnash gnats gnaws gnome
goads goals goats godly goers gofer golds golem golfs goner gongs goods goody gooey goofs goofy
goons gored gores gorge gorse gouge gowns grabs grads graft grams grate grays graze grebe grids
grime grimy grins gripe grips grist grits groin grope grout growl grows grubs gruff grump grunt
guano guava guile guise gulag gulch gulfs gulls gulps gummy gumbo guppy gurus gushy gusto gusts
gusty gutsy guyed gyros hacks hafts haiku hails hairs hakes halal haled hales halls halos halts
halve hammy hands hangs hanky hardy hared harem hares harks harms harps harpy harry harts hated
hater hates hauls haute haves havoc hawks hazed hazes heads heady heals heaps heard hears heath
heats heave heeds heels hefts heirs heist helix hells helms helps henna herbs herds hertz hewed
hewer hexed hexes hicks hider hides highs hiked hiker hikes hills hilly hilts hinds hinny hints
hippy hired hires hitch hived hives hoard hoary hobos hocks hoist holds holed holes homed homer
homes homey honed honer hones honks hoods hoofs hooks hooky hoops hoots hoped hoper hopes hoppy
horde horns hosed hoses hosts hotly hound hours hovel howdy howls hubby huffs huffy huger
hulks hulls humps humpy hunch hunks hunts hurls hurts husks husky hydra hyena hymns hyped hyper
hypes ichor icier icily icons ideas idiom idled idler idles idols idyll imbue impel inane
inbox incur inert infer ingot inlay inlet inter intro ionic irate irons isles islet itchy items
ivied jabot jacks jaded jades jails jambs jaunt jeans jeeps jeers jenny jerks jerky jetty jibed
jibes jiffy jilts jingo jinks jinns jived jives joins joist joked jokes jolts joule joust jowls
julep jumps jumpy junco junks junta kabob kapok kaput karat karma kazoo keels keens keeps kelps
kempt ketch keyed kicks kilns kilos kilts kinda kinds kings kinks kinky kited kites kiwis klutz
knave knead kneed knees knell knits knots knows kraal krill kudos laced laces lacks laden ladle
lager lairs laity lakes lamas lambs lamer lames lamps lands lanes lanky lapel larch lards largo
larks lasts latex lathe latte lauds lawns laxer layup lazed lazes leach leads leafs leafy leaks
leaky leans leaps leapt leash leech leeks leers leery lefts lefty leggy legit lemur lends lento
leper letup levee liars libel licks liege liens lifer lifts liked liken likes lilts limbo limbs
limes limns limos limps lined lines lingo links lions lipid lisps lists liter lithe litre liven
lives livid loads loafs loamy loans loath lobed lobes lochs locks locus lodes lofts logos loins
lolls lolly loner longs looks looms loons loopy loots loped lopes lords lores lorry loser loses
lossy lotto lotus louse lousy loved loves lowly lucid lucks lucre lulls lumen lumps lumpy lunge
lungs lupin lurch lured lures lurid lurks lusts lutes lying lymph lynch lyres macho macro madly
mafia magma maids mails maims mains maize makes males malls malts mamas mambo mange mangy mania
manic manly manna mares marks marts masks masts mated mates matey matte mauls maxim maybe mazes
meals mealy means meant meats meaty mecca medic meets melds melts memes memos mends menus meows
mesas messy meted metro mewed mewls micro midst miles milky mills mimed mimes mimic mince minds
mined miner mines mingy minim minis minks mints minty mired mires miser missy mists misty miter
mites mitts mixer mixes moans moats mocks modal modem modes mogul molar molds moldy moles molts
momma mommy monks moods mooed moons moors moots moped mopes moray morel mores morns morph
mossy motes motif motto mould mourn mousy moved moves mowed mower mucks mucky mucus muffs muggy
mules mulls mummy mumps munch murky mushy musky musts musty muted mutes mutts myrrh myths nabob
nadir naiad nails naked named namer names napes narcs nasal natal natty navel naves nears neath
necks needs needy neigh nerds nerdy nests newel newer newsy newts nexus nicer nicks niece nifty
nines ninja ninny nippy nixed nixes nobly nodal nodes nooks noons noose norms nosed noses nosey
notes nouns novae nubby nuked nulls numbs nylon nymph oakum oared oaths obese obeys oboes ochre
octal octet oddly odder odium odors offal ogled ogler ogles ogres oiled oiler oinks okapi okays
okras older oldie ombre omega omens omits oohed oozed oozes opals opens opine opium opted optic
orals orate osier outdo outed outgo ouija ovals ovary ovens overs overt ovine ovoid owing owlet
owned ozone paced pacer paces packs pacts padre paean pagan paged pager pages pails pains pairs
paler pales palms palsy panes pangs pansy pants panty papal papas parch pared pares parka parks
parry parse parts pasha passe pasty paths patsy patty paved paver paves pawed pawns payee payer
peaks peaky peals pears pecks peeks peels peeps peers peeve penal pence perks perky pesky pesos
pests petty phial phlox phony picks picky piers pieta piggy pikes pilaf piles pills pined pines
pings pinks pinky pinto pints pious piped piper pipes pique pitas piths pithy piton pivot pixie
plaid plait plans plats plays pleas pleat plebs plied plies plods plonk plops plots plows ploys
plugs plump plums plunk poach pocks podgy podia poems poesy poets poked pokes pokey poled poles
polio polls polyp ponds pooch pools poops popes pored pores porky ports posed poser poses posit
posts potty poult pours pouts poxes prams prate prays preen preps preys pried pries prima
primp prion prism privy prods proem profs prole promo proms prone prong props prose prowl proxy
prude psalm pucks pudgy puffs puffy puked pukes pulls pulps pulpy pulse pumas pumps punch punks
punts pupae pupal puree purer purge purls purrs pushy putts putty pygmy pylon pyres quads quaff
quark quart quash quasi quell quill quint quips quire quirt quite quits quoit quoth rabbi rabid
raced racer races racks radii radon rafts raged rages raids rails rains rainy raked rakes ramps
randy ranks rants rarer rasps raspy rates ratty raved ravel raver raves rawer rayon razed razes
razor reads reams reaps rearm rears rebar rebus rebut recap recto recur redid redox reeds reedy
reefs reeks reels reeve refit regal rehab reins relic remit remix renal rends renew rents repay
repel rerun resat reset resin rests retch retro retry reuse revel revue rheum rhino rhyme rides
rifts rigor riled riles rills rinds rings rinks riots ripen riper risen riser rises risks rites
ritzy riven rives rivet roach roads roams roans roars robed robes rocks rogue roils roles rolls
romps roofs rooks rooky rooms roomy roost roots roped roper ropes rosin rotor rouse routs roved
rover roves rowed rower ruble ruder ruffs ruing ruins ruled rules rumba rummy rumor rumps runes
rungs runny runts ruses rusks sable sabre sacks safes sages sagas sails sakes sales sally salsa
salts salty salve salvo samba sands saner sappy sassy satin satyr saute saved saver saves savvy
sawed scabs scalp scaly scamp scams scans scant scare scars scary scats scion scoff scold scoot
scorn scour scowl scram scree scrub scrum scuba scuff seals seams seamy sears seats seeds seeks
seems seeps seers segue sells sends sepia serfs serif serum sever sewed sewer shack shags shaky
shale shalt shams shank shard sheaf shear sheds sheen sheik shied shies shill shims shins ships
shire shirk shoal shoed shoes shone shook shoot shops shorn shots shove shows showy shrew shuck
shuns shunt shush shyer shyly sibyl sides sidle sighs sigma signs silks sills silos silts silty
sinew singe sings sinks sinus siren sires sisal sited sites sixes sizes skeet skein skews
skids skied skier skies skiff skimp skims skins skint skips skits skulk skunk slabs slack slain
slake slams slang slant slaps slash slats slave slays sleds sleek sleet slept slews slick slime
slims slimy sling slink slips slits slobs sloes slogs sloop slops slosh slots slows slugs slums
slung slunk slurp slurs slush slyer slyly smack smash smear smelt smite smith smock smogs smoky
smote snafu snags snail snaps snare snarl sneer snide sniff snipe snips snobs snoop snort snout
snows snowy snubs snuck snuff soaks soaps soars socks sodas sofas softy soggy soils soled soles
solos sonar songs sonic sooth soots sooty sorts souls soups soupy sours sowed sower spank spans
spars spasm spate spawn spays spear speck specs spelt spent spews spied spiel spies spiky
spill spilt spins spiny spire spite spits spitz splat splay split spoof spook spool spoor spore
spots spout sprig spuds spurn spurs spurt squab squat squaw squib stabs stags staid stall
stank staph stars stash stats stave stays stead steal steed stein stems steno steps stews stile
stilt stink stint stirs stoat stoic stoke stole stomp stony stoop stops stout strum stubs studs
stump stung stunk stunt suave sucks sudsy suing suits sulks sulky sully sumac sunup surer surfs
surly sushi swabs swami swank swans swaps sward swarm swash swath swats sways swell swigs swill
swims swine swipe swish swoon swoop swore sworn swung synod syrup tacks tacky tacos tails taint
taker takes tales talks tamed tamer tames tangy tanks taped taper tapes tapir tarns tarot tarps
tarry tarts tasks tasty tatty taunt taxed taxes taxis teaks teals teams tears teary teats techs
teddy teens teeny teeth tells temps tempt tench tends tenet tenor tense tents tepee terms terns
terra terse tests testy texts thaws theft their there these thief thins thong throb thrum thuds
thugs thump tiara tibia ticks tided tides tiers tiffs tikes tilde tiled tiler tiles tills tilts
timed times timid tines tinge tings tinny tints tipsy tires titan tithe toads toddy toffs toils
tolls tombs tomes tones tongs tools toons toots torte totem tours touts towed towns toxin toyed
tract trams traps trawl trays tread trees treks tress triad trice tries trike trill trims trios
tripe trips trite troll tromp trope trots trove truce truer trump truss tryst tubas tubby tubed
tuber tubes tucks tufts tulle tumid tumor tunas tuned tunes tunic turbo turfs turns tusks tutor
tutus tweak tweed tweet twerp twigs twill twine twins twixt tying tykes types typed typos ulcer
umbra unbar uncut undid undue unfed unify units unlit unmet unpin unset untie unwed upend upped
urged urges urine users using usurp usury uteri vales valet vamps vanes vapid vaunt veers veils
veins venal vends venom vents verbs verge verso verve vests vetch vexed vexes vials vibes vicar
video views vigil viler vines viper vireo virus visas visor vista vixen vodka vogue voids voila
volts vomit voted votes vouch vowed vying wacko wacky waded wader wades wafer wafts wager wages
waifs wails waits waive wakes waken walks walls wands waned wanes wants wards wares warms warns
warps warts warty wasps waspy watts waved waver waves waxed waxen waxes wears weeds weedy weeks
weeps weepy weirs welds wells welsh welts wends whelk whelp whiff whims whine whiny whips whist
whoop wicks widen wider wilds wiles wills wilts wimps wimpy wince winch winds wined wines wings
winks wiped wiper wipes wired wires wisps withe wives wizen woken wombs women woods wooed wooer
woofs wools woozy words wordy works worms wormy worse worst wowed wraps wrath wreak wreck wrens
wrest wring writs wrote wroth wrung wryly yahoo yanks yards yarns yawed yawls yawns years yells
yelps yetis yikes yogic yogis yokel yokes yolks yours yowls yucca yucky yummy zeros zests zilch
zincs zings zippy zones zooms admin caked calve corer loops bevel chary moult sepal strew whack
zonal alias ditzy panda dials
lavas manes milks moths roses vases
]]

ns.QuillWords = { answers = Split(ANSWERS), extra = Split(EXTRA) }
