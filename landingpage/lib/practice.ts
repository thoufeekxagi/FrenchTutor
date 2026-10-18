export const levels = ["A1", "A2", "B1", "B2"] as const;
export type Level = (typeof levels)[number];
export type Task = { scene: string; french: string; question: string; options: string[]; answer: number; explanation: string; phrase: string; meaning: string };

// Original, authored practice. These are learning exercises, not official exam questions.
export const challenges: Record<Level, Task[]> = {
  A1: [
    { scene: "At the café", french: "Bonjour ! Je voudrais un café et un croissant, s’il vous plaît.", question: "What is the person ordering?", options: ["A coffee and a croissant", "A tea and a sandwich", "Two coffees"], answer: 0, explanation: "Je voudrais means ‘I would like’. It is a polite way to order.", phrase: "Je voudrais", meaning: "I would like" },
    { scene: "Getting around", french: "Excusez-moi, où est la station de métro ?", question: "What is the person looking for?", options: ["A supermarket", "The metro station", "A taxi"], answer: 1, explanation: "Où means ‘where’. La station de métro is the metro station.", phrase: "Où est… ?", meaning: "Where is…?" },
    { scene: "Meeting someone", french: "Je m’appelle Samira. J’habite à Montréal depuis deux mois.", question: "Where does Samira live?", options: ["Paris", "Toronto", "Montréal"], answer: 2, explanation: "J’habite à means ‘I live in’. Depuis deux mois means ‘for two months’.", phrase: "J’habite à Montréal.", meaning: "I live in Montréal." },
  ],
  A2: [
    { scene: "Making an appointment", french: "Le cabinet est fermé lundi. Votre rendez-vous est mardi à quatorze heures.", question: "When is the appointment?", options: ["Monday at two", "Tuesday at two", "Tuesday at four"], answer: 1, explanation: "Mardi is Tuesday. Quatorze heures is 14:00, or two in the afternoon.", phrase: "un rendez-vous", meaning: "an appointment" },
    { scene: "On the bus", french: "Le prochain autobus arrive dans dix minutes. Vous pouvez acheter un billet à la borne.", question: "Where can you buy a ticket?", options: ["From a friend", "At a ticket machine", "Only online"], answer: 1, explanation: "Une borne is a machine or terminal. Dans dix minutes means ‘in ten minutes’.", phrase: "dans dix minutes", meaning: "in ten minutes" },
    { scene: "Weekend plans", french: "Hier, nous sommes allés au marché. Nous avons acheté des pommes pour faire une tarte.", question: "Why did they buy apples?", options: ["To make a pie", "To give to a neighbour", "For breakfast"], answer: 0, explanation: "Pour faire introduces a purpose: ‘to make’. The actions happened yesterday.", phrase: "Nous sommes allés au marché.", meaning: "We went to the market." },
  ],
  B1: [
    { scene: "A message from work", french: "En raison des travaux, l’entrée principale sera fermée demain. Veuillez utiliser la porte située derrière le bâtiment.", question: "What should employees do tomorrow?", options: ["Work from home", "Use the main entrance", "Enter through the back door"], answer: 2, explanation: "En raison de introduces a cause. Veuillez utiliser is a polite instruction to use something.", phrase: "en raison de", meaning: "because of / due to" },
    { scene: "Finding a home", french: "L’appartement me plaît, mais le loyer dépasse mon budget. Je vais demander au propriétaire si le chauffage est inclus.", question: "What is the main concern?", options: ["The apartment is too expensive", "The heating is broken", "The location is inconvenient"], answer: 0, explanation: "Dépasser mon budget means ‘exceed my budget’. Heating being included is a question, not an established fact.", phrase: "Le loyer dépasse mon budget.", meaning: "The rent exceeds my budget." },
    { scene: "Changing plans", french: "Si la météo le permet, nous organiserons le repas dans le jardin. Sinon, nous réserverons une salle.", question: "What determines where the meal takes place?", options: ["The number of guests", "The weather", "The price of the room"], answer: 1, explanation: "Si introduces a condition. Sinon means ‘otherwise’ and introduces the alternative.", phrase: "si la météo le permet", meaning: "weather permitting" },
  ],
  B2: [
    { scene: "A neighbourhood debate", french: "Bien que le projet améliore l’accès aux transports, certains résidents craignent qu’il n’entraîne une hausse des loyers.", question: "What is the residents’ concern?", options: ["Less public transport", "A possible rise in rents", "The closure of local schools"], answer: 1, explanation: "Bien que introduces a concession. Craindre que expresses fear; the ne here is expletive, not a negation.", phrase: "une hausse des loyers", meaning: "a rise in rents" },
    { scene: "An opinion piece", french: "Plutôt que d’interdire totalement les voitures au centre-ville, la municipalité gagnerait à renforcer les solutions de remplacement.", question: "What does the writer recommend?", options: ["Improve alternatives to driving", "Ban all city-centre traffic immediately", "Remove public transport"], answer: 0, explanation: "Gagnerait à means ‘would benefit from’. Plutôt que contrasts a preferred approach with another option.", phrase: "gagnerait à", meaning: "would benefit from" },
    { scene: "Working differently", french: "Le télétravail offre une souplesse appréciable, à condition que les équipes disposent d’outils adaptés et maintiennent des échanges réguliers.", question: "What qualifies the writer’s support for remote work?", options: ["It must be compulsory", "It needs suitable tools and regular communication", "It should replace all meetings"], answer: 1, explanation: "À condition que states a requirement and takes the subjunctive. The support is conditional, not absolute.", phrase: "à condition que", meaning: "provided that" },
  ],
};

export function normalizeAnswer(text: string) {
  return text.normalize("NFC").toLocaleLowerCase("fr").replace(/[’‘]/g, "'").replace(/[.,!?;:]/g, "").replace(/\s+/g, " ").trim();
}
export function wordCount(text: string) { return (text.trim().match(/[\p{L}\p{N}]+(?:[’'\-][\p{L}\p{N}]+)*/gu) ?? []).length; }
export function dayKey(date = new Date()) { return new Intl.DateTimeFormat("en-CA", { timeZone: "America/Toronto", year: "numeric", month: "2-digit", day: "2-digit" }).format(date); }
export function dailyTasks(level: Level, date = dayKey()) { const all = challenges[level]; const n = [...date].reduce((s,c)=>s+c.charCodeAt(0),0) % all.length; return [...all.slice(n), ...all.slice(0,n)]; }

export const verbs = [
  { infinitive: "être", meaning: "to be", forms: ["suis", "es", "est", "sommes", "êtes", "sont"] },
  { infinitive: "avoir", meaning: "to have", forms: ["ai", "as", "a", "avons", "avez", "ont"] },
  { infinitive: "aller", meaning: "to go", forms: ["vais", "vas", "va", "allons", "allez", "vont"] },
  { infinitive: "faire", meaning: "to do / make", forms: ["fais", "fais", "fait", "faisons", "faites", "font"] },
  { infinitive: "parler", meaning: "to speak", forms: ["parle", "parles", "parle", "parlons", "parlez", "parlent"] },
  { infinitive: "prendre", meaning: "to take", forms: ["prends", "prends", "prend", "prenons", "prenez", "prennent"] },
  { infinitive: "vouloir", meaning: "to want", forms: ["veux", "veux", "veut", "voulons", "voulez", "veulent"] },
  { infinitive: "pouvoir", meaning: "to be able to", forms: ["peux", "peux", "peut", "pouvons", "pouvez", "peuvent"] },
  { infinitive: "venir", meaning: "to come", forms: ["viens", "viens", "vient", "venons", "venez", "viennent"] },
  { infinitive: "finir", meaning: "to finish", forms: ["finis", "finis", "finit", "finissons", "finissez", "finissent"] },
  { infinitive: "savoir", meaning: "to know", forms: ["sais", "sais", "sait", "savons", "savez", "savent"] },
  { infinitive: "devoir", meaning: "to have to", forms: ["dois", "dois", "doit", "devons", "devez", "doivent"] },
];
export const pronouns = ["je", "tu", "il / elle", "nous", "vous", "ils / elles"];
export const tools = [
  { slug: "french-verb-practice", title: "Verb practice", category: "Grammar", description: "Make everyday verbs second nature. Look up a form, then put it to work.", icon: "verbs", time: "2 min", detail: "12 essential verbs · present tense" },
  { slug: "french-writing", title: "The writing desk", category: "Writing", description: "A little space to find your words. Prompts, accents and a live word count.", icon: "writing", time: "5 min", detail: "Local drafts · no account needed" },
  { slug: "french-reading", title: "Read a little French", category: "Reading", description: "Small stories about ordinary life. Read at your level and keep a useful phrase.", icon: "reading", time: "3 min", detail: "A1 to B2 · English explanations" },
  { slug: "french-keyboard", title: "French accent keyboard", category: "Everyday tools", description: "É, è, ê, ç. The right character, without remembering the shortcut.", icon: "keyboard", time: "Anytime", detail: "Type · copy · carry on" },
  { slug: "french-dictation", title: "Listen and write", category: "Listening", description: "Hear an everyday sentence, write what you catch, then check it at your level.", icon: "dictation", time: "3 min", detail: "Device speech · A1 to B2" },
  { slug: "french-sentence-builder", title: "Build a sentence", category: "Word order", description: "Put useful French words in order and see why the sentence works.", icon: "builder", time: "3 min", detail: "Tap to arrange · four levels" },
  { slug: "french-conversation", title: "Everyday conversation", category: "Conversation", description: "Choose a natural reply in short Canadian-life scenarios. No pressure, no account.", icon: "conversation", time: "4 min", detail: "Three original roleplays · A1 to B2" },
] as const;

// The public tools directory has exactly ten useful entries: this list owns
// the three broad study paths, seven focused tools, and the local notebook.
export const freeToolEntries = [
  { href: "/today", title: "Daily French practice", category: "A1–B2 · 3 min", description: "Three short questions with a clear explanation. A fresh order each day, saved on this device.", icon: "daily" },
  { href: "/learn", title: "Ten guided lessons", category: "A1–B2 · Learn at your pace", description: "Work through grammar, everyday phrases and short stories, with a useful next step in every lesson.", icon: "reading" },
  ...tools.map((tool) => ({ href: `/tools/${tool.slug}`, title: tool.title, category: tool.category, description: tool.description, icon: tool.icon })),
  { href: "/words", title: "My words", category: "Your notebook", description: "Keep useful phrases with the original sentence. Search or export your list when you need it.", icon: "words" },
] as const;

export const writingPrompts = ["Write a short message to a neighbour. Introduce yourself and invite them for a coffee.", "You cannot attend an appointment. Write a polite message asking to change the date.", "Describe a place in your city that you would recommend to a friend. Explain why.", "Should cities make public transport free? Present your opinion and one counterargument."];

export type DictationItem = { french: string; meaning: string; hint: string };
export const dictations: Record<Level, DictationItem[]> = {
  A1: [
    { french: "Je m’appelle Nadia.", meaning: "My name is Nadia.", hint: "Listen for a short introduction." },
    { french: "Un café, s’il vous plaît.", meaning: "A coffee, please.", hint: "A polite order at a café." },
    { french: "Nous habitons à Toronto.", meaning: "We live in Toronto.", hint: "Listen for the place name." },
  ],
  A2: [
    { french: "Je prends l’autobus à huit heures.", meaning: "I take the bus at eight o’clock.", hint: "Listen for the time." },
    { french: "Est-ce que vous avez une table pour deux ?", meaning: "Do you have a table for two?", hint: "A question you might ask at a restaurant." },
    { french: "Je vais reporter mon rendez-vous à demain.", meaning: "I am going to move my appointment to tomorrow.", hint: "Listen for what changes and when." },
  ],
  B1: [
    { french: "La bibliothèque ferme plus tôt pendant les jours fériés.", meaning: "The library closes earlier on public holidays.", hint: "Listen for the time comparison and the reason." },
    { french: "Nous avons dû changer de ligne à la station suivante.", meaning: "We had to change lines at the next station.", hint: "Listen for the transport phrase in the past." },
    { french: "Si le logement vous intéresse, vous pouvez envoyer une demande en ligne.", meaning: "If you are interested in the housing, you can send an application online.", hint: "Listen for the condition and the next step." },
  ],
  B2: [
    { french: "Bien que le trajet soit plus long, le train reste le choix le plus pratique.", meaning: "Although the trip is longer, the train remains the most practical choice.", hint: "Listen for the concession and the recommendation." },
    { french: "La municipalité maintiendra le service, à condition que le budget soit approuvé.", meaning: "The municipality will maintain the service, provided the budget is approved.", hint: "Listen for the condition." },
    { french: "Les travaux seront reportés si les températures demeurent trop basses.", meaning: "The work will be postponed if temperatures remain too low.", hint: "Listen for the future action and its condition." },
  ],
};

export type SentenceBuilderItem = { words: string[]; answer: string; meaning: string; note: string };
export const sentenceBuilders: Record<Level, SentenceBuilderItem[]> = {
  A1: [
    { words: ["aujourd’hui.", "travaille", "Je"], answer: "Je travaille aujourd’hui.", meaning: "I am working today.", note: "In a simple statement, put the subject before the verb." },
    { words: ["un", "voudrais", "Je", "rendez-vous."], answer: "Je voudrais un rendez-vous.", meaning: "I would like an appointment.", note: "Je voudrais is a polite way to say what you would like." },
    { words: ["à", "Nous", "Montréal.", "habitons"], answer: "Nous habitons à Montréal.", meaning: "We live in Montréal.", note: "The place follows à when you name a city." },
  ],
  A2: [
    { words: ["demain.", "suis", "libre", "Je"], answer: "Je suis libre demain.", meaning: "I am free tomorrow.", note: "Put the subject before suis, then add the time phrase." },
    { words: ["avant", "Je", "prends", "le", "travail.", "métro", "le"], answer: "Je prends le métro avant le travail.", meaning: "I take the metro before work.", note: "Put the time phrase after the action to say when it happens." },
    { words: ["m’aider ?", "Vous", "pouvez"], answer: "Vous pouvez m’aider ?", meaning: "Can you help me?", note: "The conjugated verb pouvez comes after vous. The short object m’ comes before aider." },
  ],
  B1: [
    { words: ["à", "réservé", "Nous", "l’avance.", "avons"], answer: "Nous avons réservé à l’avance.", meaning: "We booked in advance.", note: "The past participle réservé follows the auxiliary avons." },
    { words: ["pleut.", "Je", "même", "vais", "s’il", "sortir"], answer: "Je vais sortir même s’il pleut.", meaning: "I am going out even if it rains.", note: "Même si introduces a contrast; it does not change the main clause order." },
    { words: ["demander", "J’aimerais", "si", "chauffage", "inclus.", "le", "est"], answer: "J’aimerais demander si le chauffage est inclus.", meaning: "I would like to ask whether heating is included.", note: "In an indirect question, keep the subject before the verb: le chauffage est." },
  ],
  B2: [
    { words: ["soit", "Bien", "le", "que", "trajet", "reste", "plus", "long,", "train", "le", "pratique."], answer: "Bien que le trajet soit plus long, le train reste pratique.", meaning: "Although the trip is longer, the train remains practical.", note: "Bien que takes the subjunctive. The second clause returns to ordinary subject–verb order." },
    { words: ["réduire", "les", "pourrions", "si", "coûts", "nous", "planifions", "mieux.", "Nous"], answer: "Nous pourrions réduire les coûts si nous planifions mieux.", meaning: "We could reduce costs if we plan better.", note: "Use the conditional for a possible result, then si with the present tense." },
    { words: ["augmente.", "Le", "la", "à", "mesure", "service", "que", "demande", "s’améliore"], answer: "Le service s’améliore à mesure que la demande augmente.", meaning: "The service improves as demand increases.", note: "À mesure que connects two changes that happen together." },
  ],
};

export type DialogueChoice = { text: string; reply: string; feedback: string; bestFit: boolean };
export type DialogueTurn = { cue: string; prompt: string; choices: DialogueChoice[] };
export type DialogueScenario = { title: string; intro: string; turns: DialogueTurn[] };
export const dialogues: Record<Level, DialogueScenario[]> = {
  A1: [{
    title: "A first day at work",
    intro: "You have just joined a small team in Montréal. Keep the conversation going with a friendly, simple reply.",
    turns: [
      { cue: "Your colleague says", prompt: "Bonjour ! Comment vous appelez-vous ?", choices: [
        { text: "Je m’appelle Alex. Et vous ?", reply: "Je m’appelle Nadia. Enchantée !", feedback: "A clear introduction, followed by a question to keep talking.", bestFit: true },
        { text: "Il est huit heures.", reply: "Ah, oui. Le travail commence bientôt.", feedback: "That gives the time, but it does not answer the question yet.", bestFit: false },
        { text: "Je voudrais un café.", reply: "Il y a une cafétéria au premier étage.", feedback: "A useful café phrase, but your colleague asked your name.", bestFit: false },
      ] },
      { cue: "Nadia asks", prompt: "Vous habitez à Montréal ?", choices: [
        { text: "Oui, j’habite près du métro.", reply: "C’est pratique. Vous prenez quelle ligne ?", feedback: "You answer yes and add a helpful detail.", bestFit: true },
        { text: "Je m’appelle Alex.", reply: "Enchantée, Alex. Et vous habitez où ?", feedback: "You repeat your name, but she is asking where you live.", bestFit: false },
        { text: "Deux billets, s’il vous plaît.", reply: "Vous pouvez acheter des billets à la station.", feedback: "That sounds like a ticket counter. Try answering about where you live.", bestFit: false },
      ] },
      { cue: "Nadia says", prompt: "On prend un café à la pause ?", choices: [
        { text: "Oui, avec plaisir !", reply: "Super. À tout à l’heure !", feedback: "A warm, natural way to accept the invitation.", bestFit: true },
        { text: "Je ne comprends pas la station.", reply: "On parlera du métro plus tard.", feedback: "This does not answer the invitation. You can accept or decline politely.", bestFit: false },
        { text: "Le café est fermé demain.", reply: "Ah, je ne savais pas.", feedback: "That may be useful information, but it does not answer Nadia’s invitation.", bestFit: false },
      ] },
    ],
  }],
  A2: [{
    title: "Changing an appointment",
    intro: "You need to move a clinic appointment. Choose a polite response and notice how the conversation progresses.",
    turns: [
      { cue: "The receptionist asks", prompt: "Comment puis-je vous aider ?", choices: [
        { text: "J’aimerais déplacer mon rendez-vous.", reply: "Bien sûr. À quelle date est votre rendez-vous ?", feedback: "J’aimerais is a polite way to make your request.", bestFit: true },
        { text: "Il fait très froid aujourd’hui.", reply: "Oui, l’hiver est bien arrivé.", feedback: "That starts small talk, but does not explain what you need.", bestFit: false },
        { text: "Je prends l’autobus à huit heures.", reply: "D’accord. Que puis-je faire pour vous ?", feedback: "That is clear French, but it does not answer the receptionist’s question.", bestFit: false },
      ] },
      { cue: "They ask", prompt: "Quel jour vous conviendrait ?", choices: [
        { text: "Est-ce qu’il y a une place jeudi après-midi ?", reply: "Oui, à quinze heures trente.", feedback: "You ask whether a specific time is available.", bestFit: true },
        { text: "Je n’ai pas de carte de bibliothèque.", reply: "Vous êtes bien au bon endroit pour la clinique.", feedback: "That belongs to a different service. Keep the appointment context.", bestFit: false },
        { text: "Il y a deux pommes.", reply: "Je ne suis pas certaine de comprendre.", feedback: "Try asking about a day or time that works for you.", bestFit: false },
      ] },
      { cue: "The receptionist confirms", prompt: "C’est noté pour jeudi à quinze heures trente.", choices: [
        { text: "Merci beaucoup. Bonne journée !", reply: "À vous aussi !", feedback: "A polite closing that confirms you heard the new time.", bestFit: true },
        { text: "Je voudrais deux cafés.", reply: "La cafétéria est au rez-de-chaussée.", feedback: "A café order is useful elsewhere, but this appointment is now confirmed.", bestFit: false },
        { text: "Je ne sais pas où habiter.", reply: "Vous pouvez appeler un service d’aide au logement.", feedback: "That changes the subject. Thank them for confirming the appointment.", bestFit: false },
      ] },
    ],
  }],
  B1: [{
    title: "A neighbour and a delivery",
    intro: "A package was left in the wrong place. Explain the problem and agree on a practical next step.",
    turns: [
      { cue: "Your neighbour asks", prompt: "Est-ce que tout va bien avec la livraison ?", choices: [
        { text: "Le colis a été déposé devant la mauvaise porte.", reply: "Je suis désolé. Est-ce que vous savez à qui il appartient ?", feedback: "You state the problem clearly in the past tense.", bestFit: true },
        { text: "Le courrier arrive le mardi.", reply: "Oui, le facteur passe le matin.", feedback: "That mentions mail, but not the delivery problem.", bestFit: false },
        { text: "Je vais au marché demain.", reply: "Bonne idée. Il y a de bons produits frais.", feedback: "That changes the subject before explaining what went wrong.", bestFit: false },
      ] },
      { cue: "They respond", prompt: "La boîte indique le numéro 14. Est-ce que vous habitez là ?", choices: [
        { text: "Oui, c’est mon appartement. Je vais le récupérer tout de suite.", reply: "Parfait, je le garde à l’intérieur en attendant.", feedback: "You identify the address and suggest a clear next step.", bestFit: true },
        { text: "Je ne suis jamais allé au Canada.", reply: "Mais nous sommes à Montréal.", feedback: "The sentence is unrelated to the package location.", bestFit: false },
        { text: "Le chauffage est inclus dans le loyer.", reply: "Oui, c’est souvent le cas dans cet immeuble.", feedback: "That is about housing, not the package.", bestFit: false },
      ] },
      { cue: "Your neighbour says", prompt: "Je peux le déposer chez vous si vous préférez.", choices: [
        { text: "Ce serait très gentil. Merci de l’avoir gardé.", reply: "Avec plaisir. Bonne soirée !", feedback: "A courteous answer that recognizes the help they offered.", bestFit: true },
        { text: "La porte principale sera fermée demain.", reply: "Il faut utiliser l’entrée arrière, alors.", feedback: "That is a useful notice, but it does not respond to their offer.", bestFit: false },
        { text: "Nous avons acheté des pommes.", reply: "Vous allez faire une tarte ?", feedback: "That changes the topic before you acknowledge the offer.", bestFit: false },
      ] },
    ],
  }],
  B2: [{
    title: "Discussing a community service",
    intro: "Your neighbourhood is discussing a change to public transit. Make a case, acknowledge a concern, and propose a next step.",
    turns: [
      { cue: "A resident says", prompt: "Le nouveau trajet est plus rapide, mais il ne dessert plus notre rue.", choices: [
        { text: "Je comprends la préoccupation. On pourrait demander une consultation publique.", reply: "Ce serait utile. Il faudrait aussi comparer les horaires actuels.", feedback: "You acknowledge the concern and propose a constructive next step.", bestFit: true },
        { text: "Le café ferme à dix-sept heures.", reply: "Je ne vois pas le lien avec le trajet.", feedback: "This does not address the effect of the route change.", bestFit: false },
        { text: "Tout le monde devrait déménager.", reply: "Ce n’est pas une solution très réaliste.", feedback: "That dismisses the impact instead of discussing it.", bestFit: false },
      ] },
      { cue: "Another neighbour adds", prompt: "Une consultation risque de retarder le projet.", choices: [
        { text: "C’est possible, mais une décision mieux informée serait plus durable.", reply: "Je suis d’accord, tant que le calendrier reste raisonnable.", feedback: "You concede the trade-off while explaining why input still matters.", bestFit: true },
        { text: "J’ai acheté un billet hier.", reply: "Le prix a-t-il augmenté ?", feedback: "That changes from the policy discussion to a personal purchase.", bestFit: false },
        { text: "Il n’y a aucun inconvénient.", reply: "Pourtant, le calendrier vient d’être mentionné.", feedback: "The other resident has named a real trade-off; acknowledge it.", bestFit: false },
      ] },
      { cue: "The chair asks", prompt: "Quelle proposition pouvons-nous transmettre à la municipalité ?", choices: [
        { text: "Demandons une consultation et la publication des horaires comparatifs.", reply: "Je vais ajouter ces deux mesures au compte rendu.", feedback: "A concise proposal with two specific actions.", bestFit: true },
        { text: "Je ne sais pas où est la station.", reply: "Nous pouvons consulter le plan de transport après la réunion.", feedback: "That may be a separate question; the chair is asking for a proposal.", bestFit: false },
        { text: "Le temps est magnifique.", reply: "Oui, profitons-en en sortant.", feedback: "A friendly comment, but the group still needs a proposal.", bestFit: false },
      ] },
    ],
  }],
};
