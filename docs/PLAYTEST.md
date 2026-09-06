# The twenty-minute playtest

A protocol for watching one person play the opening for twenty minutes.
It is for newcomers to networking and for people who already run
networks; the same sheet serves both, with one column noting which.
Record what you see; do not fill in what you expect to see.

## Before the session

- A fresh install, a new company, learner hints on, the console font at
  its default size, a 1280x720 or larger window.
- One observer, one player. The observer does not help unless the
  player asks twice for the same thing; write down every ask.
- Start a timer when the title screen appears.

## What to record, and when

1. **First success.** The time on the clock when the first packet
   reaches the other end (the first_ping job turning green). Note what
   the player tried before it worked: which panel, which command,
   which hint. If the "Stuck? Show me the commands" button was pressed,
   note the job and the minute.
2. **Understanding a fault.** When the guided outage starts, note in
   the player's own words what they think is wrong before they gather
   evidence, then after each evidence layer. Note whether they can say
   which port and why before pressing restore, and whether they chose
   assisted restore.
3. **Decisions versus navigation.** Every minute, tick one column:
   deciding (reading the brief, choosing a plan, reasoning about a
   bottleneck) or navigating (looking for a panel, a button, a port).
   Three navigating ticks in a row is a finding; write what they were
   looking for.
4. **The sale night.** Which launch plan they chose and why, in their
   words. Whether they changed anything before the waves. What they
   watched during the waves. Their reaction to the debrief line about
   their own contribution.
5. **Memorable moments.** At twenty minutes stop the clock and ask three
   questions, recording the answers verbatim: what was the best moment;
   what was the most confusing moment; what would you do next if you
   kept playing.

## After the session

- Copy the sheet into the session's own file under docs/playtests/
  named by date and player type (newcomer or engineer). Never merge two
  sessions into one sheet.
- File each navigating streak, each unanswered ask and each confusion
  as its own issue with the minute mark and the player's words.
- Do not invent findings. A session with nothing to report is a
  session with nothing to report.
