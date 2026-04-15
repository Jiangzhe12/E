import Foundation

enum CommonWordBank {
    static let coreWords: [String] = {
        let words = coreWordText
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .map { String($0).lowercased() }
            .filter { !$0.isEmpty }
        var seen: Set<String> = []
        var result: [String] = []
        result.reserveCapacity(words.count)
        for word in words where shouldIncludeCoreWord(word) {
            if seen.insert(word).inserted {
                result.append(word)
            }
        }
        return result
    }()

    static var extendedWords: [String] { extendedBundle.words }

    /// Whether `/usr/share/dict/web2` was successfully read on first access.
    /// When false, `extendedWords` is empty and the stats card can show that
    /// the word-bank is running in degraded mode.
    static var extendedWordsSourceAvailable: Bool { extendedBundle.available }

    private static let extendedBundle: (words: [String], available: Bool) = {
        let coreSet = Set(coreWords)
        let sourcePath = "/usr/share/dict/web2"

        let rawText: String
        do {
            rawText = try String(contentsOfFile: sourcePath, encoding: .utf8)
        } catch {
            NSLog("[CommonWordBank] extended word source unavailable at %@: %@",
                  sourcePath, error.localizedDescription)
            return (words: [], available: false)
        }

        var seen: Set<String> = []
        var result: [String] = []
        result.reserveCapacity(7000)

        for line in rawText.split(whereSeparator: { $0.isWhitespace || $0.isNewline }) {
            if result.count >= 7000 { break }
            let word = String(line).lowercased()
            guard !coreSet.contains(word), shouldIncludeExtendedWord(word) else {
                continue
            }
            if seen.insert(word).inserted {
                result.append(word)
            }
        }

        return (words: result, available: true)
    }()

    static var totalWordCount: Int {
        coreWords.count + extendedWords.count
    }

    static func exampleSentence(for word: String) -> String {
        let lowercased = word.lowercased()
        if commonVerbs.contains(lowercased) {
            return "I try to \(lowercased) in English every day."
        }
        if commonAdjectives.contains(lowercased) {
            return "The explanation is clear and \(lowercased)."
        }
        return "\"\(lowercased)\" is a useful word in daily English conversations."
    }

    private static func shouldIncludeCoreWord(_ word: String) -> Bool {
        guard word.count >= 2 && word.count <= 15 else {
            return false
        }
        guard word.allSatisfy({ $0.isLetter }) else {
            return false
        }
        return true
    }

    private static func shouldIncludeExtendedWord(_ word: String) -> Bool {
        guard word.count >= 3 && word.count <= 10 else {
            return false
        }
        guard word.allSatisfy({ $0.isLetter }) else {
            return false
        }

        let vowelCount = word.filter { "aeiou".contains($0) }.count
        guard vowelCount >= 1 else {
            return false
        }

        if rareSuffixes.contains(where: { word.hasSuffix($0) }) {
            return false
        }

        var consonantRun = 0
        for character in word {
            if "aeiou".contains(character) {
                consonantRun = 0
            } else {
                consonantRun += 1
                if consonantRun >= 4 {
                    return false
                }
            }
        }

        return true
    }

    private static let rareSuffixes: [String] = [
        "eth", "esth", "ieth", "eous", "aceous", "tude", "hood"
    ]

    private static let commonVerbs: Set<String> = [
        "be", "have", "do", "say", "get", "make", "go", "know", "take", "see", "come", "think", "look",
        "want", "give", "use", "find", "tell", "ask", "work", "seem", "feel", "try", "leave", "call",
        "need", "become", "start", "play", "move", "live", "believe", "bring", "happen", "write", "sit",
        "stand", "lose", "pay", "meet", "include", "continue", "set", "learn", "change", "lead", "understand",
        "watch", "follow", "stop", "create", "speak", "read", "allow", "add", "spend", "grow", "open",
        "walk", "win", "offer", "remember", "love", "consider", "appear", "buy", "wait", "serve", "die",
        "send", "expect", "build", "stay", "fall", "cut", "reach", "kill", "raise", "pass", "sell",
        "require", "report", "decide", "pull", "return", "explain", "hope", "develop", "carry", "break",
        "receive", "agree", "support", "hit", "produce", "eat", "cover", "catch", "draw", "choose",
        "cause", "point", "listen", "realize", "place", "close", "involve", "increase", "improve", "practice"
    ]

    private static let commonAdjectives: Set<String> = [
        "good", "new", "first", "last", "long", "great", "little", "own", "other", "old", "right", "big",
        "high", "different", "small", "large", "next", "early", "young", "important", "few", "public", "bad",
        "same", "able", "clear", "full", "easy", "hard", "free", "strong", "simple", "available", "likely",
        "ready", "short", "single", "special", "whole", "best", "major", "real", "common", "main", "local",
        "sure", "human", "general", "specific", "recent", "current", "basic", "final", "happy", "serious"
    ]

    private static let coreWordText = """
    the be to of and a in that have i it for not on with he as you do at this but his by from they we say her she
    or an will my one all would there their what so up out if about who get which go me when make can like time no
    just him know take people into year your good some could them see other than then now look only come its over think
    also back after use two how our work first well way even new want because any these give day most us is are was were
    been being am does did done had has having said says say go goes went gone get gets got gotten make makes made know
    knows knew known think thinks thought take takes took taken see sees saw seen come comes came coming look looks looked
    want wants wanted give gives gave given use uses used find finds found tell tells told ask asks asked work works worked
    seem seems seemed feel feels felt try tries tried leave leaves left call calls called need needs needed become becomes
    became put puts mean means meant keep keeps kept let lets begin begins began begun help helps helped talk talks talked
    turn turns turned start starts started show shows showed shown hear hears heard play plays played run runs ran move moves
    moved live lives lived believe believes believed bring brings brought happen happens happened write writes wrote written
    provide provides provided sit sits sat stand stands stood lose loses lost pay pays paid meet meets met include includes
    included continue continues continued set sets learn learns learned change changes changed lead leads led understand
    understands understood watch watches watched follow follows followed stop stops stopped create creates created speak
    speaks spoke spoken read reads allow allows allowed add adds added spend spends spent grow grows grew grown open opens
    opened walk walks walked win wins won offer offers offered remember remembers remembered love loves loved consider
    considers considered appear appears appeared buy buys bought wait waits waited serve serves served die dies died send
    sends sent expect expects expected build builds built stay stays stayed fall falls fell fallen cut cuts cut reach reaches
    reached kill kills killed remain remains remained suggest suggests suggested raise raises raised pass passes passed sell
    sells sold require requires required report reports reported decide decides decided pull pulls pulled return returns
    returned explain explains explained hope hopes hoped develop develops developed carry carries carried break breaks broke
    broken receive receives received agree agrees agreed support supports supported hit hits hit produce produces produced
    eat eats ate eaten cover covers covered catch catches caught draw draws drew drawn choose chooses chose chosen cause causes
    caused point points pointed listen listens listened realize realizes realized place places placed close closes closed
    involve involves involved increase increases increased improve improves improved practice practices practiced study studies
    studied teach teaches taught learn learning writing speaking reading listening traveling planning organizing reviewing
    language word phrase sentence paragraph story article message email meeting interview project design code test review
    result process progress challenge habit focus effort memory goal system team company customer user client product service
    feature update issue bug fix quality speed performance security privacy data model table record history summary dashboard
    report chart metric stat overview trend insight context topic lesson card question answer option feedback coach scenario
    translation dictionary meaning definition phonetic pronunciation example usage pattern grammar vocabulary speaking fluency
    confidence consistency routine schedule calendar time date today tomorrow yesterday morning afternoon evening night week
    month year daily weekly monthly always usually often sometimes never again still already yet soon later before after
    above below near far left right top bottom inside outside around through between among during without within across along
    about against toward under over behind beside beyond despite except inside outside plus minus around about like unlike
    and or not if because although though while where when why how what which who whom whose whatever whoever whenever
    this that these those here there now then very more most less least much many few several enough all both each every
    either neither another other others same different similar various certain such own whole half part piece side end
    start middle center level line point area place space world country city town village community school college university
    class course teacher student parent child kid friend family group member leader manager engineer designer developer
    writer reader speaker listener learner beginner expert beginner intermediate advanced simple complex easy difficult
    possible impossible useful helpful meaningful valuable practical realistic specific clear direct concise detailed complete
    accurate correct wrong true false safe risky stable unstable flexible fixed dynamic static local global public private
    personal official formal informal casual professional technical creative logical emotional physical mental social digital
    online offline mobile desktop laptop tablet phone computer keyboard screen window panel button checkbox toggle picker
    list item row column card section sidebar detail content title subtitle label icon image color background gradient style
    layout spacing padding margin border corner shadow opacity animation transition gesture hover click tap drag drop scroll
    input output request response load save delete update refresh retry cancel submit confirm open close start stop pause
    resume sync async task queue thread actor state store cache disk memory network server client api endpoint token key
    value object array map set function method class struct enum protocol extension module package target build compile run
    launch install deploy release debug log trace monitor alert notify schedule automate workflow branch commit merge review
    test case suite scenario assertion verify validate check inspect measure benchmark optimize refactor simplify maintain
    document note comment message summary plan roadmap milestone priority blocker risk impact effort estimate scope status
    active pending completed failed success ready done continue repeat rotate cycle shuffle random deterministic sequence
    choose select filter sort search query match compare combine split merge transform convert normalize format parse decode
    encode import export attach detach connect disconnect enable disable allow deny trust verify approve reject accept
    familiar unfamiliar remember forget recognize understand master review revise repeat practice drill train improve grow
    confidence habit streak count total today weekly monthly yearly overview statistics familiarized mastered pending words
    common frequent useful practical everyday daily basic core advanced conversation workplace travel technology education
    health fitness food drink coffee tea water breakfast lunch dinner restaurant airport station hotel ticket passport
    boarding luggage baggage flight train bus taxi subway street road traffic direction map weather sunny cloudy rainy windy
    hot cold warm cool spring summer autumn winter holiday weekend weekday office meeting deadline email message call video
    camera microphone speaker headphone battery charge power signal connection internet website browser search engine account
    password profile setting option preference language region timezone currency payment order invoice price cost budget
    money bank market business startup growth revenue profit loss value mission vision strategy execution operation support
    help center documentation tutorial guide example sample template checklist report summary analytics overview insight
    learn teach explain describe discuss share present introduce conclude compare evaluate improve deliver complete achieve
    success failure opportunity challenge solution problem question answer idea concept approach method technique tool
    framework library dependency integration migration compatibility reliability maintainability scalability availability
    resilience observability transparency accountability ownership collaboration communication teamwork leadership mentorship
    curiosity discipline patience persistence motivation inspiration creativity imagination innovation experimentation learning
    reflection feedback adjustment adaptation iteration evolution improvement excellence quality craftsmanship responsibility
    empathy respect trust honesty integrity fairness inclusion diversity accessibility sustainability wellbeing balance focus
    energy attention awareness mindfulness decision judgment reasoning evidence data fact assumption hypothesis validation
    conclusion recommendation action outcome impact benefit tradeoff constraint requirement specification acceptance criteria
    definition implementation deployment operation maintenance monitoring incident response recovery prevention mitigation
    onboarding kickoff planning estimation execution review retrospective documentation knowledge sharing handoff followup
    customer discovery user research interview survey analysis synthesis prioritization design prototyping testing iteration
    backlog sprint release changelog version rollback hotfix patch upgrade downgrade compatibility deprecation replacement
    model app application software hardware platform ecosystem environment workspace repository source resource script toolchain
    terminal command shell path directory file folder permissions sandbox approval escalation policy process workflow routine
    """
}
