// ─── Crop Data ────────────────────────────────────────────────────────────────
// Organised alphabetically. Duplicates removed (one canonical name per crop).
// Every crop has a matching entry in commonVarieties.

const List<String> commonCrops = [
  // ── Cereals & Millets ──────────────────────────────────────────────────────
  "Bajra (Pearl Millet)",
  "Barley",
  "Jowar (Sorghum)",
  "Maize",
  "Oats",
  "Ragi (Finger Millet)",
  "Rice",
  "Rye",
  "Wheat",

  // ── Pulses ─────────────────────────────────────────────────────────────────
  "Arhar (Tur / Pigeon Pea)",
  "Chickpea",
  "Cowpea",
  "Green Gram (Moong)",
  "Horse Gram",
  "Kidney Bean",
  "Lentil",
  "Lima Bean",
  "Moth Bean",
  "Soybean",
  "Urad (Black Gram)",

  // ── Oilseeds ───────────────────────────────────────────────────────────────
  "Castor",
  "Flax (Linseed)",
  "Groundnut",
  "Mustard",
  "Safflower",
  "Sesame",
  "Sunflower",

  // ── Fibre Crops ────────────────────────────────────────────────────────────
  "Cotton",
  "Hemp",
  "Jute",

  // ── Sugar & Starch ─────────────────────────────────────────────────────────
  "Cassava",
  "Sugarcane",
  "Sweet Potato",

  // ── Vegetables ─────────────────────────────────────────────────────────────
  "Ash Gourd",
  "Beetroot",
  "Bitter Gourd",
  "Bottle Gourd",
  "Brinjal (Eggplant)",
  "Broccoli",
  "Brussels Sprout",
  "Cabbage",
  "Capsicum (Bell Pepper)",
  "Carrot",
  "Cauliflower",
  "Celery",
  "Chilli",
  "Cluster Beans (Guar)",
  "Cucumber",
  "Drumstick (Moringa)",
  "Fenugreek",
  "Garlic",
  "Ginger",
  "Ivy Gourd",
  "Kale",
  "Leek",
  "Lettuce",
  "Okra (Bhindi)",
  "Onion",
  "Parsley",
  "Pea",
  "Pointed Gourd",
  "Potato",
  "Pumpkin",
  "Radish",
  "Ridge Gourd",
  "Snake Gourd",
  "Spinach",
  "Tomato",
  "Turnip",
  "Yam",
  "Yellow Squash",
  "Zucchini",

  // ── Fruits ─────────────────────────────────────────────────────────────────
  "Amla (Indian Gooseberry)",
  "Apple",
  "Apricot",
  "Avocado",
  "Banana",
  "Ber (Indian Jujube)",
  "Blueberry",
  "Coconut",
  "Custard Apple",
  "Date Palm",
  "Fig",
  "Grape",
  "Guava",
  "Jackfruit",
  "Kiwi",
  "Lemon / Lime",
  "Lychee",
  "Mango",
  "Melon",
  "Mulberry",
  "Orange",
  "Papaya",
  "Passion Fruit",
  "Peach",
  "Pear",
  "Pineapple",
  "Plum",
  "Pomegranate",
  "Pomelo",
  "Raspberry",
  "Sapota (Chikoo)",
  "Strawberry",
  "Sweet Lime (Mosambi)",
  "Tamarind",
  "Watermelon",

  // ── Plantation & Spices ────────────────────────────────────────────────────
  "Ajwain",
  "Arecanut",
  "Bamboo",
  "Basil",
  "Betel Vine",
  "Cacao",
  "Cardamom",
  "Clove",
  "Coffee",
  "Coriander",
  "Cumin (Jeera)",
  "Dill",
  "Fennel",
  "Lavender",
  "Mint",
  "Neem",
  "Nutmeg",
  "Pepper (Black)",
  "Rubber",
  "Saffron",
  "Tea",
  "Tobacco",
  "Turmeric",
  "Vanilla",

  // ── Flowers & Ornamentals ──────────────────────────────────────────────────
  "Chrysanthemum",
  "Dahlia",
  "Gerbera",
  "Gladiolus",
  "Jasmine",
  "Marigold",
  "Rose",
  "Tuberose",
  "Zinnia",

  // ── Other ──────────────────────────────────────────────────────────────────
  "Alfalfa",
  "Amaranth",
  "Asparagus",
  "Buckwheat",
  "Clover",
  "Hops",
  "Olive",
  "Quinoa",
];

// Every crop in commonCrops has a matching entry here.
// Variety-filtered dropdown: when a crop is selected, only its varieties show.
const Map<String, List<String>> commonVarieties = {

  // ── Cereals & Millets ──────────────────────────────────────────────────────
  "Bajra (Pearl Millet)": [
    "HHB-67", "Pusa Composite 443", "ICMH 356", "Raj-171",
    "GHB-558", "ICTP-8203", "Proagro 9444",
  ],
  "Barley": [
    "Jyoti", "Azad", "K-141", "DL-88", "RD-2552", "DWRB-73",
    "Himani", "Manjula",
  ],
  "Jowar (Sorghum)": [
    "CSH-16", "CSH-17", "CSV-15", "M-35-1", "SPV-462",
    "Phule Chitra", "RSLG-262",
  ],
  "Maize": [
    "Ganga-11", "Pusa Hybrid-2", "DHM-117", "HQPM-1",
    "Bio-9637", "NK-6240", "Pioneer 30V92",
  ],
  "Oats": [
    "Kent", "Algerian", "HFO-114", "OS-6", "Palampur-1",
    "JHO-822", "Sabzar",
  ],
  "Ragi (Finger Millet)": [
    "GPU-28", "MR-6", "Indaf-5", "Phule Nachani",
    "VL-149", "PR-202", "HR-374",
  ],
  "Rice": [
    "IR-36", "Swarna", "Pusa Basmati-1", "BPT 5204 (Samba Masuri)",
    "Jaya", "MTU-7029", "Govind", "Pusa-44",
    "1121 Basmati", "Lalat", "DRR Dhan-310",
  ],
  "Rye": [
    "Lokum", "Rillito", "Danko", "Prima", "Wheeler",
  ],
  "Wheat": [
    "HD-2967", "WH-542", "PBW-343", "GW-322", "K-9107",
    "Raj-4120", "Lok-1", "Kalyansona", "HD-3086", "HI-8498",
  ],

  // ── Pulses ─────────────────────────────────────────────────────────────────
  "Arhar (Tur / Pigeon Pea)": [
    "ICPL-87119 (Asha)", "BDN-2", "CO-6", "NDA-2",
    "Pusa-992", "GT-101", "Maruti",
  ],
  "Chickpea": [
    "Pusa 256", "JG-11", "Desi Chana", "Kabuli Chana",
    "KAK-2", "Pusa 1053", "ICCC-37",
  ],
  "Cowpea": [
    "Pusa Komal", "V-16", "Arka Garima", "EC-4216",
    "Gomati", "Lobia-1", "SEB-2",
  ],
  "Green Gram (Moong)": [
    "Pusa Vishal", "Samrat", "PDM-139", "HUM-1",
    "MH-421", "SML-668", "K-851",
  ],
  "Horse Gram": [
    "HPK-4", "PHG-9", "CRHG-01", "Paiyur-1",
    "VZM-2", "Dapoli-1",
  ],
  "Kidney Bean": [
    "Contender", "Blue Lake", "Pusa Parvati", "VL Boni-1",
    "Arka Komal", "SVM-1",
  ],
  "Lentil": [
    "Pusa Vaibhav", "DPL-62", "Noori", "Sehore 74-3",
    "L-4076", "IPL-81", "Malka-13",
  ],
  "Lima Bean": [
    "Henderson Bush", "Fordhook-242", "King of Garden",
    "Pusa-4", "Edith",
  ],
  "Moth Bean": [
    "RMO-257", "CAZM-181", "HMO-229", "FMO-45", "Pratap Moth-1",
  ],
  "Soybean": [
    "JS-335", "NRC-7", "Pusa-16", "PK-472",
    "MACS-450", "Shilajeet", "JS-9305",
  ],
  "Urad (Black Gram)": [
    "Pant U-19", "IPU-94-1", "TAU-1", "VBN-6",
    "LBG-752", "KU-96-3", "PU-19",
  ],

  // ── Oilseeds ───────────────────────────────────────────────────────────────
  "Castor": [
    "GCH-4", "DCH-177", "YRCH-1", "48-1",
    "Aruna", "Phule Kranti", "SKI-215",
  ],
  "Flax (Linseed)": [
    "Gaurav", "NL-260", "Shekhar", "Surbhi",
    "Rashmi", "Meera", "T-397",
  ],
  "Groundnut": [
    "TAG-24", "TG-26", "GG-2", "ICGS-11",
    "Kaushal", "JL-24", "R-9251", "Dharani",
  ],
  "Mustard": [
    "Pusa Bold", "Pusa Bahar", "Varuna", "Rohini",
    "Aashirwad", "RH-30", "Kranti", "DRMR-150",
  ],
  "Safflower": [
    "A-1", "PBNS-12", "Sharda", "NARI-6",
    "Bhima", "Manjira", "CO-1",
  ],
  "Sesame": [
    "RT-346", "GT-10", "Rama", "VRI-1",
    "SI-1736", "Pragati", "Tarun",
  ],
  "Sunflower": [
    "KBSH-44", "MSFH-17", "Sunola", "CO-2",
    "DRSH-1", "Sungold", "BSH-1",
  ],

  // ── Fibre Crops ────────────────────────────────────────────────────────────
  "Cotton": [
    "Bt Cotton", "MCU-5", "LRA-5166", "Suraj",
    "Khandwa-2", "JK Durga", "RCH-2", "ACH-33-2",
  ],
  "Hemp": [
    "NFC-1", "Carmagnola", "Felina-32", "Finola",
    "Anka", "Bialobrzeskie",
  ],
  "Jute": [
    "JRO-524 (Navin)", "JRO-8432", "OM-1", "Suren",
    "D-154", "Bidhan Patas-2",
  ],

  // ── Sugar & Starch ─────────────────────────────────────────────────────────
  "Cassava": [
    "H-226", "Sree Vijaya", "Sree Sahya", "CO-3",
    "Sree Rekha", "MVS-1", "MNga-1",
  ],
  "Sugarcane": [
    "Co-86032", "Co-0238", "CoJ-88", "CoS-8436",
    "CoSe-92423", "CoC-671", "Co-419",
  ],
  "Sweet Potato": [
    "Sree Bhadra", "Sree Nandini", "Sree Ratna",
    "Sree Arun", "CIP-440038", "Gouri",
  ],

  // ── Vegetables ─────────────────────────────────────────────────────────────
  "Ash Gourd": [
    "CO-1", "Indu", "Kashi Ujwal", "IARI Selection",
    "MH-2", "Pusa Ujwal",
  ],
  "Beetroot": [
    "Detroit Dark Red", "Crimson Globe", "Early Wonder",
    "Chioggia", "Golden Beet", "Pusa Madhuram",
  ],
  "Bitter Gourd": [
    "Pusa Do Mausami", "Arka Harit", "CO-1",
    "Priya", "Hirkani", "MDU-1",
  ],
  "Bottle Gourd": [
    "Pusa Summer Prolific Long", "Pusa Naveen", "CO-1",
    "Arka Bahar", "IIHR-11", "Samrat",
  ],
  "Brinjal (Eggplant)": [
    "Pusa Purple Long", "Arka Nidhi", "Pusa Anmol",
    "CO-1", "Swarna Manjari", "Pant Samrat",
  ],
  "Broccoli": [
    "Pusa KTS-1", "Green Magic", "Palam Vichitra",
    "Fiesta", "Marathon", "Lucky",
  ],
  "Brussels Sprout": [
    "Hilds Ideal", "Long Island Improved", "Jade Cross",
    "Franklin", "Falstaff",
  ],
  "Cabbage": [
    "Golden Acre", "Pusa Drum Head", "Pride of India",
    "CO-1", "Green Express", "Quisto",
  ],
  "Capsicum (Bell Pepper)": [
    "California Wonder", "Yolo Wonder", "Bharat",
    "Arka Gaurav", "Arka Basant", "Indra",
  ],
  "Carrot": [
    "Pusa Kesar", "Nantes", "Chantenay", "Pusa Yamdagni",
    "Early Nantes", "Pusa Meghali",
  ],
  "Cauliflower": [
    "Pusa Snowball K-1", "Early Kunwari", "Improved Japanese",
    "Pusa Dipali", "Harabhari", "NS-51",
  ],
  "Celery": [
    "Utah-52-70", "Golden Self Blanching", "Pascal",
    "Tango", "Conquistador",
  ],
  "Chilli": [
    "Pusa Jwala", "Bhagya Laxmi", "Arka Lohit",
    "NP-46A", "Kashmiri Red", "Byadgi Dabbi",
    "Guntur Sannam", "LCA-206",
  ],
  "Cluster Beans (Guar)": [
    "Pusa Naubahar", "Pusa Sadabahar", "FS-277",
    "RGC-936", "HG-365", "Ageta-112",
  ],
  "Cucumber": [
    "Pusa Uday", "Poinsett-76", "Green Long",
    "Pointsett-76", "Arka Sheetal", "PCUC-10",
  ],
  "Drumstick (Moringa)": [
    "PKM-1", "PKM-2", "Rohit-1", "CO-1",
    "Bhagya", "Dhanraj",
  ],
  "Fenugreek": [
    "Pusa Early Bunching", "RMt-1", "HM-103",
    "Lam Selection-1", "CO-1", "Rajendra Kanti",
  ],
  "Garlic": [
    "Yamuna Safed", "Agrifound White", "G-1",
    "G-50", "Godavari", "HG-6", "Ooty-1",
  ],
  "Ginger": [
    "Maran", "Nadia", "Suprabha", "Suruchi",
    "Suravi", "Himachal", "Rio-de-Janeiro",
  ],
  "Ivy Gourd": [
    "Arka Neelachal Kankada", "TNAU-Selection",
    "Priya", "Indira", "CO-1",
  ],
  "Kale": [
    "Scotch Curled", "Lacinato (Dinosaur)", "Red Russian",
    "Siberian", "Premier",
  ],
  "Leek": [
    "Broad London", "American Flag", "Titan",
    "King Richard", "Pandora",
  ],
  "Lettuce": [
    "Great Lakes", "Pusa Rohini", "Iceberg",
    "Romaine", "Butter Head", "Lollo Rossa",
  ],
  "Okra (Bhindi)": [
    "Pusa A-4", "Arka Anamika", "Varsha Uphar",
    "Hisar Unnat", "VRO-6", "Parbhani Kranti",
  ],
  "Onion": [
    "Agrifound Dark Red", "Pusa Red", "N-53",
    "Bhima Raj", "Arka Niketan", "Nasik Red", "AFLR-3",
  ],
  "Parsley": [
    "Plain / Italian", "Curled / Moss", "Hamburg",
    "Titan", "Darki",
  ],
  "Pea": [
    "Arkel", "Bonneville", "Pusa Pramod",
    "VL Matar-7", "Azad Matar-1", "T-163",
  ],
  "Pointed Gourd": [
    "Swarna Rekha", "Rajendra Pointed Gourd-1",
    "IARI Selection", "Kashi Alankar", "DGH-1",
  ],
  "Potato": [
    "Kufri Jyoti", "Kufri Chandramukhi", "Kufri Badshah",
    "Kufri Sindhuri", "Kufri Pukhraj", "Kufri Chipsona-1",
  ],
  "Pumpkin": [
    "Pusa Viswas", "Arka Suryamukhi", "CO-1",
    "Ambili", "Kashi Harit", "TNAU Hybrid-1",
  ],
  "Radish": [
    "Pusa Chetki", "Pusa Desi", "Pusa Rashmi",
    "Japanese White", "Arka Nishant", "Rapid Red",
  ],
  "Ridge Gourd": [
    "Pusa Nasdar", "CO-1", "Satputia",
    "Arka Sumeet", "Kashi Divya", "Sweta",
  ],
  "Snake Gourd": [
    "TA-19", "CO-1", "Kaumudi",
    "Konkan Sweta", "PLR-1",
  ],
  "Spinach": [
    "Pusa Harit", "Pusa Jyoti", "All Green",
    "Banerjee Giant", "Savoy", "Hybrid No. 7",
  ],
  "Tomato": [
    "Pusa Ruby", "Arka Vikas", "CO-3",
    "Pusa-120", "Solan Gola", "Hisar Arun",
    "NS-585", "Arka Abha",
  ],
  "Turnip": [
    "Pusa Sweti", "Purple Top White Globe",
    "Pusa Chandrima", "Golden Ball", "Milan White",
  ],
  "Yam": [
    "Shree Reshmi", "Gajendra", "Sree Keerthi",
    "Karthika", "Harsha",
  ],
  "Yellow Squash": [
    "Early Prolific Straightneck", "Goldbar",
    "Superpik", "Butter Stick", "Multipik",
  ],
  "Zucchini": [
    "Black Beauty", "Grey Zucchini", "Gold Rush",
    "Patio Star", "Astia",
  ],

  // ── Fruits ─────────────────────────────────────────────────────────────────
  "Amla (Indian Gooseberry)": [
    "Chakaiya", "Francis", "NA-6", "NA-7",
    "Kanchan", "BSR-1", "Neelam",
  ],
  "Apple": [
    "Royal Delicious", "Fuji", "Gala", "Granny Smith",
    "Ambri", "McIntosh", "Chaubattia Princess",
  ],
  "Apricot": [
    "New Castle", "NJA-1", "Shakarpara", "Moorpark",
    "Goldrich", "Early Shipley",
  ],
  "Avocado": [
    "Hass", "Fuerte", "Pinkerton", "Reed",
    "Bacon", "Green Gold",
  ],
  "Banana": [
    "Cavendish", "Robusta", "Grand Nain", "Red Banana",
    "Nendran", "Poovan", "Rasthali", "Karpooravalli",
  ],
  "Ber (Indian Jujube)": [
    "Gola", "Umran", "Kaithali", "Seo",
    "Mundia", "Banarasi Pewandi", "NB-5",
  ],
  "Blueberry": [
    "Bluecrop", "Duke", "Patriot", "Jersey",
    "O'Neal", "Brightwell",
  ],
  "Coconut": [
    "West Coast Tall", "East Coast Tall",
    "Chowghat Orange Dwarf", "Malayan Yellow Dwarf",
    "Tiptur Tall", "D×T Hybrid",
  ],
  "Custard Apple": [
    "Balanagar", "Red Sitaphal", "Arka Sahan",
    "NMK-1", "Washington",
  ],
  "Date Palm": [
    "Medjool", "Deglet Nour", "Zahidi", "Barhee",
    "Halawy", "Khadrawy",
  ],
  "Fig": [
    "Poona Fig", "Dinkar", "Brown Turkey", "Kadota",
    "Deanna", "Osborn's Prolific",
  ],
  "Grape": [
    "Anab-e-Shahi", "Thompson Seedless", "Pusa Seedless",
    "Bangalore Blue", "Sharad Seedless", "Flame Seedless",
    "Italia",
  ],
  "Guava": [
    "Allahabad Safeda", "L-49 (Lucknow-49)", "Lalit",
    "Pant Prabhat", "Arka Mridula", "Hisar Safeda",
  ],
  "Jackfruit": [
    "Singapore Jack", "Rudrakshi", "Hazari",
    "Swarna", "Kapa", "Velipala",
  ],
  "Kiwi": [
    "Allison", "Bruno", "Hayward", "Monty",
    "Abbott", "Vincent",
  ],
  "Lemon / Lime": [
    "Vikram", "Pusa Udit", "Sai Sarbati",
    "Tahiti Lime", "Eureka", "PKM-1",
  ],
  "Lychee": [
    "Shahi", "China", "Rose Scented", "Early Large Red",
    "Bombai", "Calcuttia",
  ],
  "Mango": [
    "Alphonso", "Dasheri", "Langra", "Himsagar",
    "Kesar", "Totapuri", "Chausa", "Banganapalli",
    "Neelam", "Mallika",
  ],
  "Melon": [
    "Pusa Sharbati", "Hara Madhu", "Arka Rajhans",
    "MHY-5", "Pusa Madhuras", "Durgapura Madhu",
  ],
  "Mulberry": [
    "S-36", "S-54", "Goshoerami", "Kanva-2",
    "Victory-1", "TR-10",
  ],
  "Orange": [
    "Nagpur Mandarin", "Coorg Mandarin", "Kinnow",
    "Blood Red", "Hamlin", "Valencia",
  ],
  "Papaya": [
    "Pusa Delicious", "Pusa Dwarf", "Co-1",
    "Coorg Honey Dew", "Washington", "Red Lady",
  ],
  "Passion Fruit": [
    "Purple Passion", "Yellow Passion", "Sweet Granadilla",
    "Kaveri", "PKM-1",
  ],
  "Peach": [
    "Shan-i-Punjab", "Florda Prince", "Saharanpur Sharbati",
    "Early Grande", "Prabhat",
  ],
  "Pear": [
    "Punjab Beauty", "Patham Pear", "Lepine",
    "Conference", "Bartlett", "CITH-P-1",
  ],
  "Pineapple": [
    "Kew", "Queen", "Mauritius", "Giant Kew",
    "Lakshmi", "MD-2",
  ],
  "Plum": [
    "Santa Rosa", "Frontier", "Kala Amritsari",
    "Titron", "Alubokhara", "Satluj Purple",
  ],
  "Pomegranate": [
    "Ganesh", "Bhagwa", "Mridula", "Ruby",
    "Jalore Seedless", "Dholka",
  ],
  "Pomelo": [
    "Thong Dee", "Red Shaddock", "Nambour Delight",
    "Hirado Buntan",
  ],
  "Raspberry": [
    "Heritage", "Autumn Bliss", "Glen Coe",
    "Cascade Delight", "Tulameen",
  ],
  "Sapota (Chikoo)": [
    "Cricket Ball", "Kalipatti", "Baramati",
    "DHS-1", "Oval", "DSH-2",
  ],
  "Strawberry": [
    "Chandler", "Fern", "Sweet Charlie",
    "Ofra", "Camarosa", "Pajaro",
  ],
  "Sweet Lime (Mosambi)": [
    "Mosambi", "Sathgudi", "Phule Mosambi",
    "NMK Lime-1", "California",
  ],
  "Tamarind": [
    "PKM-1", "Urigam", "Pratisthan",
    "No.263", "DTS-1",
  ],
  "Watermelon": [
    "Sugar Baby", "Arka Manik", "Asahi Yamato",
    "Durgapura Lal", "Kiran", "NS-295",
  ],

  // ── Plantation & Spices ────────────────────────────────────────────────────
  "Ajwain": [
    "AA-2", "Gujarat Ajwain-1", "RA-1-80", "RA-19-80",
  ],
  "Arecanut": [
    "Mangala", "Sumangala", "Sreemangala",
    "Hirehalli Dwarf", "South Kanara",
  ],
  "Bamboo": [
    "Bambusa bambos", "Dendrocalamus strictus",
    "B. tulda", "D. hamiltonii", "Thyrsostachys oliveri",
  ],
  "Basil": [
    "Genovese", "Thai Basil", "Tulsi (Holy Basil)",
    "Lemon Basil", "Purple Basil",
  ],
  "Betel Vine": [
    "Bangla", "Meetha", "Kapoori", "Calcutta",
    "Sanchi", "Magahi",
  ],
  "Cacao": [
    "Forastero", "Criollo", "Trinitario",
    "CCN-51", "ICS-60",
  ],
  "Cardamom": [
    "ICRI-1", "ICRI-2", "Mudigere-1", "Mudigere-2",
    "Njallani", "Malabar",
  ],
  "Clove": [
    "Zanzibar", "Pemba", "Siputih",
    "Sitoraja", "CPCRI-1",
  ],
  "Coffee": [
    "Arabica", "Robusta", "S.795", "Cauvery",
    "Selection 9", "Chandragiri",
  ],
  "Coriander": [
    "CO-1", "CO-2", "RCr-41", "CS-6",
    "Hisar Anand", "Pant Haritima",
  ],
  "Cumin (Jeera)": [
    "GC-1", "RZ-19", "RZ-209", "MC-43",
    "Gujarat Jeera-1", "Pusa Pragati",
  ],
  "Dill": [
    "Fernleaf", "Mammoth", "Bouquet",
    "Long Island", "Herkules",
  ],
  "Fennel": [
    "Gujarat Fennel-1", "PF-35", "RF-101",
    "Azad Sauf", "CO-1",
  ],
  "Lavender": [
    "Hidcote", "Munstead", "Vera", "Grosso", "Phenomenal",
  ],
  "Mint": [
    "Kosi (MAS-1)", "Himalaya", "Hybrid-77",
    "Peppermint", "Spearmint",
  ],
  "Neem": [
    "Desi Neem", "Melia Azadirachta",
    "Azadirachta indica (High AZA)", "VRI-1",
  ],
  "Nutmeg": [
    "CPCRI-1", "CPCRI-2", "Konkan Sugandha",
    "ACC-4", "TNC-1",
  ],
  "Pepper (Black)": [
    "Panniyur-1", "Sreekara", "Subhakara",
    "Panchami", "Pournami", "Karimunda",
  ],
  "Rubber": [
    "RRII-105", "RRII-430", "GT-1",
    "RRIM-600", "PB-235", "BPM-24",
  ],
  "Saffron": [
    "Kashmir Saffron", "Italian Saffron",
    "Spanish Saffron", "Iranian Saffron",
  ],
  "Tea": [
    "Assam Type", "China Type", "Cambod Type",
    "TV-1", "UPASI-9", "Darjeeling Clone",
  ],
  "Tobacco": [
    "Virginia Flue-Cured", "Burley", "Natu",
    "Lanka", "FCV", "Chewing Tobacco",
  ],
  "Turmeric": [
    "Pusa Manjal", "Roma", "Suroma",
    "Rajendra Sonia", "Suvarna", "BSR-2",
    "Krishna", "Megha Turmeric-1",
  ],
  "Vanilla": [
    "Vanilla planifolia", "V. tahitensis",
    "V. pompona", "Tahitian Vanilla",
  ],

  // ── Flowers & Ornamentals ──────────────────────────────────────────────────
  "Chrysanthemum": [
    "Rajat", "Hemant", "Pooja", "Flirt",
    "Thai Yellow", "Yellow Star", "Lalima",
  ],
  "Dahlia": [
    "Karma Sangria", "Bishop of Llandaff", "Thomas Edison",
    "Arabian Night", "Seattle", "Mystique",
  ],
  "Gerbera": [
    "Freddy", "Balance", "Rosalin", "Karine",
    "Ruby Red", "Sweet Dreams", "Cartouche",
  ],
  "Gladiolus": [
    "Pusa Pitamber", "Aldebaran", "White Prosperity",
    "Jacksonville Gold", "Sylvia", "Vink's Glory",
  ],
  "Jasmine": [
    "CO-1", "CO-2", "Arka Surabhi", "PKM-1",
    "Gundu Malli", "Pitchi", "Iruvatchi",
  ],
  "Marigold": [
    "Pusa Narangi Gainda", "Pusa Basanti Gainda", "Inca Gold",
    "African Giant Orange", "Crackerjack", "Alumia Vanilla",
  ],
  "Rose": [
    "First Red", "Gladiator", "Top Secret",
    "Samantha", "Pusa Gaurav", "Super Gold",
    "Happiness", "Gruss an Teplitz",
  ],
  "Tuberose": [
    "Single Flowering", "Double Flowering", "Shringar",
    "Prajwal", "Vaibhav", "Suvarna",
  ],
  "Zinnia": [
    "Dreamland Scarlet", "Profusion Orange", "Benary's Giant Coral",
    "Zahara Yellow", "Giant Limone",
  ],

  // ── Other ──────────────────────────────────────────────────────────────────
  "Alfalfa": [
    "Anand-2", "RL-88", "T-9", "S-244", "Sirsa-9",
  ],
  "Amaranth": [
    "Pusa Kiran", "Pusa Lal Chaulai", "CO-1",
    "AAU Amaranth-1", "Annapurna",
  ],
  "Asparagus": [
    "Mary Washington", "Jersey Giant", "Purple Passion",
    "UC-157", "Atlas",
  ],
  "Buckwheat": [
    "VL Buckwheat-1", "PRB-1", "Shimla B-1",
    "Himdhan", "Sagar",
  ],
  "Clover": [
    "Red Clover", "White Clover", "Crimson Clover",
    "Alsike Clover", "Strawberry Clover",
  ],
  "Hops": [
    "Cascade", "Centennial", "Chinook",
    "Fuggle", "Hallertau", "Saaz",
  ],
  "Olive": [
    "Arbequina", "Manzanilla", "Frantoio",
    "Koroneiki", "Picholine", "Leccino",
  ],
  "Quinoa": [
    "Titicaca", "Atlas", "Cherry Vanilla",
    "Rainbow", "Colorado No. 407",
  ],
};

const List<String> irrigationTypes = [
  'Drip Irrigation',
  'Sprinkler Irrigation',
  'Center Pivot',
  'Surface / Flood',
  'Furrow Irrigation',
  'Sub-surface Drip',
  'Rainfed',
];

const List<String> growthStages = [
  'Sowing (0%)',
  'Germination (10%)',
  'Vegetative (25%)',
  'Tillering / Branching (40%)',
  'Flowering (60%)',
  'Grain / Fruit Fill (75%)',
  'Ripening / Maturity (90%)',
  'Harvest Ready (100%)',
];
