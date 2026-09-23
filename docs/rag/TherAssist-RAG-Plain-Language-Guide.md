# Where TherAssist's Advice Comes From
## Plain-language guide for presenters

*As of 2026-09-23 · Muhammad (Mohsin) Sardar*

## The one-paragraph answer

TherAssist listens to the session, and every few seconds it takes the last thing that was said and looks it up in a library of therapy manuals, published research and crisis protocols that our clinical team chose. It hands the passages it finds, together with the transcript, to the AI, and asks for one short suggestion. So when a card appears on the therapist's screen, it was written with real clinical sources open on the desk, and the session summary shows which sources those were. The AI proposes; the therapist decides.

## The library

The library is a curated set of clinical documents, about 3,460 in total, held in Google's search service inside SUNY's own cloud project; nothing in it comes from the open internet at run time.

| Shelf | What is on it | Documents |
| --- | --- | --- |
| Therapy manuals | Core evidence-based treatment protocols (the "how to" of CBT, exposure, activation) | 94 |
| Safety and crisis | Suicide-risk assessment standards, including the 988 Lifeline guidance, and crisis protocols | 9 |
| CBT research | Published clinical research papers on cognitive-behavioral therapy | 196 |
| Behavioral activation | Research and protocols on scheduling activities to lift depression | 76 |
| DBT | Dialectical behavior therapy sources | 6 |
| IPT | Interpersonal psychotherapy sources | 75 |
| Session transcripts | De-identified therapy transcript excerpts, used to recognise patterns such as avoidance or a strained alliance | 3,000 |

Two more shelves exist (motivational interviewing and trauma-informed care) but are not yet connected to the app. What is deliberately not in the library: the patient's own record, notes the therapist types, previous sessions, and anything from the web. The AI can only ground a suggestion in what the clinical team put on these shelves.

## The journey of a sentence

From a spoken sentence to a card on the screen takes about two seconds, and the lookup happens in the middle of it.

```
Words spoken
  → Transcript (speech-to-text)
  → Every ~8 new words: look up the last minute of conversation
  → Library search, 4 shelves at once
  → 3 to 9 matching passages
  → AI reads the passages together with the transcript
  → One short suggestion on the therapist's screen
```

Reading the flow: the words are transcribed as they are spoken; roughly every eight new words the system takes the most recent stretch of conversation and searches four shelves of the library with it; the passages that match are placed in front of the AI together with the transcript; the AI writes one suggestion; the therapist sees it as a card.

A real example from the Jane Doe demo session. Jane and Dr. Alvarez were reviewing homework: "Can you tell me how it went filling out that activity log? … those couple of hours on Saturday, was that when you were planning to bake cookies for your sister? Yeah, I actually did it, she came over." Those words became the search. The library returned nine passages, from the behavioral-activation and CBT shelves, about scheduling activities and reinforcing the ones a client completes. Two seconds later the card read **"Behavioral Activation Opportunity"**, suggesting the therapist reinforce the completed activity and connect it to Jane's sense of being able to act. No one typed a keyword; the patient's own words did the looking up.

## What makes it look something up

Three things decide when the library is consulted and which shelves are opened; none of them is a hidden keyword list that the patient has to hit.

1. **Talking.** Every eight or so new words that the transcription has finalised start a lookup. Silence, half-finished words and typed notes do not. If the room is quiet for the first twenty seconds, one lookup runs anyway so the screen is never empty.
2. **The modality the therapist chose.** At the start of a session the therapist picks CBT, DBT or IPT. That choice opens the matching shelves: CBT opens the CBT research and behavioral-activation shelves; DBT opens the DBT shelf; IPT the IPT shelf. The therapy-manuals shelf and the safety shelf are open in every session.
3. **Safety words.** Separately from the library search, a fixed list of about 90 phrases is checked on every lookup: talk of suicide or not wanting to be alive, self-harm, harming others, abuse, overdose or relapse. If any appears, the system forces a safety card whatever the AI would otherwise have said, tells the AI which phrase it heard, and gives the deeper analysis more room to reason. This list is a safety net under the AI, not the only way safety is noticed.

So the answer to "what words trigger it?" is: any words, because the search uses the last minute or so of the conversation itself as the question. The safety phrases are the one exception where a specific word changes what happens.

## Why this matters, and the honest limits

An AI that answers from memory alone can sound confident and be wrong; an AI that must first read passages from a vetted library is anchored to what the field has actually published, and it can show its sources.

- **Grounded, not improvised.** Every suggestion is written with retrieved passages in front of the model. The session summary lists its citations, so a clinician can see which manual or paper a recommendation leaned on.
- **Curated by clinicians.** The shelves were chosen and filled by the clinical team. Adding a new protocol means adding documents to a shelf, not retraining a model.
- **Same rule online and in the clinic.** The version on the laptop and the version in SUNY's cloud use the same library and the same steps; we verify this after every change by reading the system's own logs, which record each lookup and how many passages it returned.

The limits, said plainly:

- The search can come back with little or nothing relevant. The AI is then working from the transcript and its general training, and the card will be more generic.
- The AI still chooses the wording. Grounding narrows what it says; it does not make it infallible.
- The therapist decides. Cards are prompts to consider, never instructions; nothing is sent to the patient.
- The library is only as good as what is on the shelves. The DBT shelf, for instance, has six documents today; CBT has almost two hundred.

## Talking points and likely questions

Three sentences to say on stage, then the questions an audience usually asks.

- "Every suggestion you'll see was written after the system looked up the last minute of conversation in a library our clinicians built: therapy manuals, published research, crisis protocols."
- "The patient's own words are the search. Nobody types anything; roughly every eight words it looks again."
- "The AI proposes, with its sources; the therapist decides. And the safety net is a fixed list of crisis phrases that forces a safety card no matter what."

| Likely question | Short answer |
| --- | --- |
| Is it searching the internet? | No. Only SUNY's own library of about 3,500 clinical documents, inside SUNY's cloud project. |
| What if it finds nothing? | The card is more generic. The logs show how many passages each lookup returned, so we know when that happens. |
| Does it diagnose? | No. It reads for process and risk and suggests; it does not label the patient. |
| Where does the patient's data go? | The transcript is processed inside the SUNY cloud project in the US; nothing goes to the public internet, and nothing is used to train models. |
| How do you know it used the library? | Every lookup writes a log line with the shelves searched and the passages found; we check them after each change. |
| Can it miss a crisis? | The fixed phrase list catches explicit language regardless of the AI, and the safety shelf is consulted on every call; subtle cues still depend on the model and, above all, the clinician. |
| Who chose what is in the library? | The clinical team. Adding a protocol means adding documents to a shelf. |
| How fast is it? | About two seconds from the words being spoken to the card; the deeper analysis and the end-of-session summary take longer. |
