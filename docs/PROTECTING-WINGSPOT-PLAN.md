# Protecting Wingspot: name, code and the repository

A plan, not legal advice. It lists what can be protected, what cannot, and what to decide and do. Anything that needs a legal opinion is marked **Lawyer**. Owner todos are marked **Owner**. Fees and rules change, so check the current ones at each office before filing.

## The short answer

- **The idea cannot be protected.** "A logbook for spotters and flyers" is free for anyone to build. Copyright protects a concrete work, not the idea behind it. In the EU, software "as such" and business methods are excluded from patents, and a patent would also need a new technical invention.
- **What can be protected:** the name and logo (trademark), the code, texts, icons and screenshots (copyright, automatic), the private parts (trade secrets), and the places where the name lives (domain, store names, handles).
- **Nothing stops someone from building a similar app.** What can be stopped is copying of Wingspot's code and assets, and use of the name Wingspot or a confusingly similar name.

## 1. Name and logo (trademark): the strongest tool

| Step | Who | Notes |
|---|---|---|
| Search for conflicts before filing | Owner | DPMA register (Germany), EUIPO eSearch plus (EU), TMview (many offices at once), WIPO Global Brand Database. Also search the App Store, Google Play and the web for "Wingspot" and close spellings ("Wing Spot", "Wingspotter") |
| Pick the classes | Owner, **Lawyer** optional | Likely class 9 (downloadable software and apps) and class 42 (software as a service). Class 41 (entertainment, communities) and 38 (social networking services) are worth a thought because of the feed and friends |
| Decide where | Owner | DPMA: Germany only, cheaper. EUIPO: the whole EU, higher fee. A later international extension (WIPO, "Madrid system") builds on either. Wingspot is offered in the stores worldwide, so decide which markets matter |
| File the word mark first | Owner | The word "Wingspot" protects any lettering. The logo can follow later, once the design is final |
| Keep the filing receipt and the date | Owner | The filing date is the priority date |
| Use the mark as filed and watch for copies | Owner | A mark that is not used for years can be removed. Set an alert in the store search and a yearly search |

Order of work: search, then file the word mark, then the logo. Do not publish a rename or a new logo until the search is done.

**Not covered by a trademark:** a similar app under a different name. A trademark also does not give rights in the word "wing" or "spot" alone.

## 2. The code and the repository: decide the licence

**Facts today** (as of this document):

- The GitHub repository `markusseidel/wingspot` is **public** (created on 3 November 2026).
- [LICENSE](../LICENSE) is the **MIT licence**, copyright Markus Seidel. MIT lets anyone use, copy, change, publish and **sell** the code, with no payment and no permission, as long as the licence text stays with it.
- The repository holds iOS, Android, the backend (database migrations, edge functions) and the documentation, including plans like this one.
- Hidden badge definitions are not in the repository (`backend/private/`, ignored by git).
- At the time of writing: 2 stars, 0 forks.

**What that means:** copyright exists automatically, but MIT gives it away for the whole repository. Whoever has the code may rebuild Wingspot and publish it, under any name that is not Wingspot (a trademark would still stop the name).

**Changing the licence only affects the future.** Copies already taken keep the MIT terms for the versions they have. Anything committed from now on can have different terms.

Options:

| Option | What it does | Cost |
|---|---|---|
| **A. Keep MIT** | Open source, easy for helpers, no protection from copying | Anyone may copy the app |
| **B. Make the repository private** | Code is hidden again. Needs a plan for the CI, the public docs and any link to the code. Fresh clones of the old public history exist already | Loses the public face and outside help |
| **C. Switch to a source-available licence** (for example a licence that allows reading and contributing but forbids offering a competing product) | The code stays visible, copying for a competing app is forbidden. It is **not open source** by the usual definition | Some contributors and tools may avoid it. Pick the exact licence text with a lawyer |
| **D. Split the repository** | A public part (contracts, test vectors, docs) and a private part (apps, backend) | Work to split, CI and links must change |

Recommendation for discussion: C or D if keeping a competing clone out matters more than being open source; A if openness and community help matter more. Decide before more is built, because each commit is released under the licence of the day. **Owner**

When changing the licence:

1. Make a **Lawyer** check the wording for the EU, and whether outside contributors have given any rights. Today the commit history is single-author, so there are no outside contributions to clear. Check again before accepting any pull request from someone else.
2. Add a contributor agreement (a short CLA or a "developer certificate of origin") before outside code is accepted. This keeps the right to relicense.
3. Change `LICENSE` and the line in `README.md`, and say clearly from which commit the new terms apply.
4. Keep a copy of the MIT text for the commits released under it.

## 3. Trade secrets: keep private what must stay private

- Hidden badges, their names, rules and texts stay out of the repository, the docs and issue replies (already a standing rule).
- Do not put private keys, tokens, the production database content, user data, unpublished business plans or partner terms in the repository, in issues or in the docs.
- Mark the private documents as confidential, and give outside helpers an NDA before they see anything private. **Lawyer** for the template.
- A trade secret only counts if reasonable steps are taken to keep it secret. A public document is not a secret any more.

## 4. Names and accounts around the name

| Item | Todo | Owner |
|---|---|---|
| Domain `wingspot.site` | Already owned. Add `wingspot.app`, `.com` and the German `.de` if they are free and affordable, and set them to forward. Turn on auto-renew | Owner |
| App Store and Google Play names | Names are first come first served. Reserve the final name by creating the listing early. A later trademark helps in a dispute | Owner |
| Social handles | Reserve "wingspot" on the platforms that matter, even if unused | Owner |
| Developer accounts | Keep them in one clear owner's name. Later, a company account (Apple needs a D-U-N-S number for organisations) | Owner |
| Registering a company | A company (for example a UG or GmbH in Germany) holds the trademark, the accounts and the code. Moving rights from a person to a company later needs a written assignment. Ask a tax adviser and a **Lawyer** when revenue starts | Owner |

## 5. What to do about a copycat

- **Same name or look-alike name:** a trademark objection, then a notice to the store (Apple and Google both take down infringing names and icons).
- **Copied images, texts, icons or code (with a clear licence breach):** a copyright notice to the store or the host (GitHub has a takedown form). Keep dated screenshots and the commit history as proof.
- **A similar app with its own code and name:** nothing to do. This is allowed.

Keep dated evidence of what Wingspot is and when it was published: first TestFlight build, first commit, first public post. The history of this repository already serves as one. **Owner**

## 6. Order of work

1. Search the name "Wingspot" (section 1) and the store names. This is free, and it decides everything after it.
2. Decide the licence question (section 2).
3. File the word mark (section 1). If a conflict appears in step 1, decide on a rename **before** any public launch.
4. Reserve the extra domains and handles (section 4).
5. Put the privacy-sensitive parts under NDA or leave them out of the repository (section 3).
6. Later, with revenue: company, rights assignment, logo mark (sections 1 and 4).

## Open questions

1. Is open source part of what Wingspot wants to be (the community, the friends who help), or is protection from copying more important? This decides option A to D.
2. Which markets matter in the first two years: Germany, the EU, or worldwide? This decides DPMA, EUIPO or an international filing.
3. Is a company planned, and when? The trademark and the accounts are best held by the entity that will earn the money.
4. Does anyone besides the owner have commits or plan to send a pull request? If yes, a contributor agreement comes first.
5. Is a lawyer budget available for a one-hour check of the name search, the class list and the licence text?
