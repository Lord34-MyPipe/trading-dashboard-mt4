# CompensationGrid_EA — EA de grille de compensation à risque borné (MT5)

> ⚠️ **À lire absolument.** Aucune stratégie de grille / compensation / martingale n'est « sans risque ».
> Cet EA **borne** le risque (perte maximale connue d'avance grâce à un *stop dur en euros*), il ne
> l'**élimine pas**. Le scénario qui casse toutes les grilles, c'est une **tendance forte sans retour**.
> Ici, ce scénario te coûte au maximum la limite que tu fixes (ex. 3 % = 300 € sur 10 000 €), puis l'EA
> coupe tout. **Teste TOUJOURS en compte DÉMO Roboforex pendant plusieurs semaines avant le réel.**

---

## 1. Le principe (en clair)

Tu m'as demandé : *« trader un maximum de lots, toujours sortir en positif ou à break-even, sans risque »*.

La partie « sans risque » est impossible. Voici la version honnête et tenable :

1. L'EA ouvre une **première position** (selon un signal de tendance simple, configurable).
2. Si le marché va **contre** la position, il **ajoute des positions** au même sens, espacées d'un certain
   nombre de pips (la « grille »). Le prix moyen du panier se rapproche du marché.
3. Dès que le **panier entier** atteint un **objectif de profit** (ex. +30 €), il **ferme tout**.
4. Si la grille est **pleine** (nombre max de paliers atteint), l'EA se contente d'une sortie à
   **break-even** (≈ 0 €) dès que possible — exactement ce que tu décris.
5. **Filet de sécurité (le point clé)** : si la perte flottante du panier dépasse le **STOP DUR**
   (ex. −300 €), l'EA **liquide tout immédiatement**. C'est ce qui transforme la martingale « qui peut tout
   perdre » en risque **borné et connu**.

C'est la logique de « compensation » que tu voulais, mais **sécurisée par un plafond de perte**.

---

## 2. Pourquoi « max de lots + pas risqué » est contradictoire

- Plus tu ouvres de lots, plus chaque pip vaut cher → plus la perte potentielle est grande.
- Les EA vendus comme « 100 % gagnants » cachent le risque dans la **queue de distribution** : ils gagnent
  des dizaines de fois de suite, puis **une seule** mauvaise tendance efface tout.
- La seule façon responsable de « maximiser le volume » est de le faire **dans une enveloppe de perte
  plafonnée**. C'est exactement ce que fait le paramètre `InpMaxBasketLossPct`.

Garde ça en tête : **ce n'est pas une machine à imprimer de l'argent.** C'est un outil avec un risque maîtrisé.

---

## 3. Installation sous MT5

1. Ouvre MetaTrader 5 (Roboforex).
2. Menu **Fichier → Ouvrir le dossier de données**.
3. Copie `CompensationGrid_EA.mq5` dans `MQL5/Experts/`.
4. Dans MetaEditor (F4), ouvre le fichier et **Compile** (F7). Il doit compiler **sans erreur**.
5. Dans MT5, **active** « Algo Trading » (bouton en haut).
6. Glisse l'EA sur le graphique du symbole voulu (ex. **EURUSD M15**).
7. Coche **« Autoriser le trading algorithmique »** dans la fenêtre de l'EA.

---

## 4. Roboforex — choix du compte et spreads

Les spreads comptent énormément pour une grille (on ouvre beaucoup de positions).

| Type de compte Roboforex | Spread EURUSD typique | Commission | Recommandé ? |
|--------------------------|------------------------|------------|--------------|
| **Pro-Cent / Pro**       | ~1.0–1.3 pip           | 0          | OK débutant  |
| **ECN**                  | ~0.0–0.4 pip           | ~20 $/lot A/R | ✅ **idéal grille** |
| **Prime**                | ~0.0–0.6 pip           | ~10 $/lot A/R | ✅ bon compromis |
| Standard                 | ~1.3+ pip variable     | 0          | à éviter pour grille |

➡️ **Recommandation : compte ECN ou Prime**, spreads serrés. Renseigne la commission réelle dans
`InpCommissionPerLot` (commission **aller-retour en € pour 1.0 lot**). Sur ECN ≈ 7 € ; sur Prime ≈ 4 €.
Le P&L du panier est calculé **net de cette commission**, donc le break-even est un vrai break-even.

Vérifie le spread en direct : il s'affiche dans le **panneau de l'EA** sur le graphique. Si Roboforex
affiche des points 5 chiffres, 1 pip = 10 points. `InpMaxSpreadPoints = 25` ≈ 2.5 pips max pour ouvrir.

---

## 5. Réglages recommandés pour 10 000 € (prudent)

> Commence **encore plus prudent que ça** en démo, puis ajuste.

```
--- Signal ---
InpEntryMode          = 1        (suit la tendance MA)
InpMAPeriod           = 50
InpMATimeframe        = PERIOD_M15

--- Lots ---
InpFixedStartLot      = 0.01     (commence en lot FIXE minuscule au début !)
InpRiskPercentStart   = 0.30     (utilisé seulement si FixedStartLot = 0)
InpLotMultiplier      = 1.30     (martingale douce ; mets 1.0 pour averaging pur, plus sûr)
InpMaxSingleLot       = 1.0
InpMaxTotalLot        = 5.0

--- Grille ---
InpMaxLevels          = 6
InpGridStepPips       = 25
InpDynamicStep        = true     (espacement ATR : s'élargit quand ça bouge)
InpATRStepFactor      = 1.0

--- Sorties ---
InpProfitTargetMoney  = 30.0     (objectif panier)
InpUseBEExit          = true
InpBreakEvenMoney     = 2.0
InpTrailBasket        = true
InpTrailStartMoney    = 20.0
InpTrailGiveBackMoney = 10.0

--- SÉCURITÉ (le plus important) ---
InpMaxBasketLossPct   = 3.0      (STOP DUR : 300 € max de perte par panier)
InpDailyLossLimitPct  = 5.0      (stop la journée à -500 €)
InpMinMarginLevel     = 300.0

--- Filtres ---
InpMaxSpreadPoints    = 25
InpCommissionPerLot   = 7.0      (ADAPTE à ton compte Roboforex réel !)
InpUseTradingHours    = true
InpStartHour          = 7
InpEndHour            = 21
InpTradeFriday        = false
```

### Pour « plus de volume » mais toujours borné
Augmente `InpFixedStartLot` (0.05, 0.10…) et/ou `InpMaxLevels`, **mais laisse `InpMaxBasketLossPct`
identique**. Tu trades plus de lots, et ta perte max reste plafonnée à 3 %. C'est le bon réglage.

### Pour le plus sûr possible
- `InpLotMultiplier = 1.0` (pas de martingale, pur averaging).
- `InpMaxBasketLossPct = 2.0`.
- `InpProfitTargetMoney` plus petit (objectifs plus fréquents et plus modestes).

---

## 6. Comment lire le panneau sur le graphique

```
Positions panier: 3 / 6      <- paliers ouverts / max
Volume cumulé: 0.07 lots
P&L panier (net): +12.40 €   <- profit flottant NET (commission déduite)
Objectif: +30.00 €
STOP DUR: -300.00 €          <- au-delà, l'EA coupe tout
P&L du jour: +45.00 €
Trading jour: actif
```

---

## 7. Limites et risques à connaître

- **Tendance forte** : la grille empile des pertes jusqu'au STOP DUR. Tu perds la limite (ex. 300 €), pas plus.
- **Gap de week-end / news** : le prix peut sauter au-delà du STOP DUR (slippage). La perte réelle peut
  dépasser légèrement la limite. C'est pour ça qu'on évite le vendredi (`InpTradeFriday=false`) et qu'on
  peut éviter les grosses news.
- **Swap** : garder des positions plusieurs nuits coûte du swap (intégré au P&L net).
- **Sur-optimisation** : ne « tune » pas les paramètres pour qu'ils brillent sur le backtest passé.

---

## 8. Avant le réel — checklist

- [ ] Compilé sans erreur dans MetaEditor.
- [ ] Backtest dans le **Strategy Tester** MT5 (mode « Toutes les ticks », plusieurs mois).
- [ ] Testé en **compte démo Roboforex** ≥ 2–4 semaines avec les lots réels visés.
- [ ] `InpCommissionPerLot` réglé sur la **vraie** commission de ton compte.
- [ ] STOP DUR confirmé : provoque volontairement une perte en démo et vérifie que l'EA coupe bien tout.
- [ ] VPS en place (cf. dossier `vps-setup/`) pour que l'EA tourne 24/5.

---

*Cet EA est fourni à titre éducatif. Le trading sur marge comporte un risque de perte. Tu es seul
responsable de l'usage que tu en fais. Commence petit, en démo.*
