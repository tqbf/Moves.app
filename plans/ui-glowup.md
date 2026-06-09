# UI glow-up punch list

Filtered down from a 76-item external review to the 30 most important
**fit/finish/usability** items. Semantic / information-architecture
concerns (what "Available" means, what a "thread" is, how the IA should
be reorganized, naming/vocabulary, sidebar grouping) are deliberately
excluded — the reviewer didn't know the model, that's a separate fight,
and not what this list is about.

Numbered fresh for this list — original review numbers are not
preserved.

---

## Trust-breaking bugs

1. **Natural-language date parser display lies.** Typing
   `test API tomorrow at 3pm` previews as **"Today at 3:00 PM"**. Must
   read "Tomorrow at 3:00 PM" (and ideally show the calendar date on
   hover / in secondary text).

2. **Scheduling phrase stays in the task title.** The preview title
   becomes `test API tomorrow` while the due chip separately says the
   parsed time. Title should strip the parsed temporal phrase
   (`test API`) when parsing confidence is high.

3. **Row truncation looks sloppy.** Subtitles render with both
   duplicated ellipses in source and tail-mode truncation collisions
   (`Write an mOS blog post, or something about meta-apps....`). Use
   `Text(...).lineLimit(1).truncationMode(.tail)` and ensure the source
   string doesn't already contain `...`.

4. **"New thread…" field reads as disabled.** Low contrast placeholder
   + a + icon that looks dim. Increase contrast; make the whole field
   clickable/focusable.

## Pane structure & layout grid

5. **Main pane has no header.** Selected sidebar destination is the
   only label for the content. Add a pane title + count + optional
   sort/filter controls inside the content area.

6. **Content alignment isn't consistent across panes.** Available
   starts near x ≈ 390, Current's card starts farther right/down,
   Threads has its own indent. Define and enforce: pane inset, header
   height, row leading, card leading, control spacing.

7. **Top toolbar strip is empty.** Wasted real estate at the top of the
   main window. Should hold global actions: quick add, search, view
   options, working-status indicator.

8. **Empty space isn't doing any work.** Most of the window is blank.
   Use it for one of: selected-task preview, day plan summary, keyboard
   hints, or a "nothing selected" surface with one obvious next action.

9. **No selected-detail / inspector surface.** Clicking a row in a list
   pane reveals nothing in-pane — the lists are pure launchers. Either
   open a detail view, add an inspector column, or expand the row.

## Current card

10. **Current card lacks operational detail.** Should show: title,
    elapsed time prominently (`00:16`), started clock time
    (`Started 2:14 PM`), deadline if any, and the action set.

11. **Current card buttons have no hierarchy.** `Open thread`, `Stop`,
    `Park` are equal-weight default buttons in a big card. Set primary
    (Open Thread), destructive/terminal (Stop / Complete), secondary
    (Park) — with width and color matching role.

## Row anatomy

12. **Task rows lack anatomy.** Just stacked text + separators today.
    Needs: title, status / next action, deadline indicator, optional
    project tag, selection/open affordance.

13. **Row height is cramped vs the canvas.** Bump to ~56–68pt so the
    two-line preview reads as intentional, not accidental.

14. **Separators dominate the content.** Horizontal lines are more
    visually coherent than the actual task data. Lighten the dividers
    or increase content weight + spacing.

15. **Weak visual hierarchy in Available/Ready.** Title + subtitle
    weights are reasonable but nothing else guides the eye. Add
    deadline badges, status badges, or grouping headers — the list
    should visibly answer "what should I do next?".

## Command overlay

16. **Parsed-preview line lacks visual grammar.** Today it mashes the
    cleaned title, parsed due, and destination together. Separate them
    visibly: cleaned title (`test API`), parsed due (`Tomorrow at 3:00
    PM`), destination (`Ready` / `Deadlines` / `Thread`).

17. **Due-date chips are display-only.** Click on the orange chip must
    open a date/time editor (or cycle through common presets).
    Natural-language parsing is never reliable enough to be read-only.

18. **Alert offsets row appears when there's no due date.** Hide it
    until a due date is parsed — otherwise it adds cognitive load.

19. **No confidence/failure state in the overlay.** Parser can be
    wrong. Need escape hatches: clickable due chip, removable due chip,
    a warning color when ambiguous, a tooltip showing the full
    interpreted date.

20. **Return-to-create affordance is too subtle.** The hooked Return
    glyph is barely visible. Use a stronger hint ("Press Return to
    create") or a trailing Create button.

21. **Esc-to-cancel isn't surfaced.** Users need to know Escape
    dismisses. Add an Esc hint, or a subtle close icon.

## Deadlines & urgency throughout

22. **Deadlines don't appear on normal task rows.** A task app must
    expose time pressure in the regular queue, not only on the
    Deadlines pane. Show the due chip inline on rows with a due_at.

23. **Reuse the orange due chip everywhere.** The orange `Today at 3:00
    PM` chip in the command overlay is the right visual language for
    deadlines — port it into task rows and the Current card so the
    deadline vocabulary is consistent.

24. **Explicit visual states for time pressure.** Design the row
    rendering for: due today, due tomorrow, overdue (within the
    one-hour flag window), no due date, parked-with-due-date. Right
    now overdue items look normal — that's how task apps fail hardest.

## Interaction states

25. **Hover / selection / focus row states aren't designed.** macOS
    desktop conventions: hovered row, selected row, focused row,
    active/current row, disabled/unavailable row — each needs a
    distinct treatment.

26. **No hover-revealed row affordances.** Available rows offer no
    Start / Open / Park / Due controls on hover. Add row-level action
    icons that appear on hover or focus.

27. **No right-click context menus.** macOS users expect right-click
    on every row: Start, Open, Rename, Set deadline, Park, Delete /
    Archive, Copy markdown.

28. **Empty states are missing per destination.** Each sidebar
    destination needs a designed empty state with copy and one
    action — Current empty → "Start something from Ready"; Captured
    empty → "Quick capture with ⌘N"; Deadlines empty → "No upcoming
    deadlines"; Time Log empty → "Work sessions will appear here".

## Type & color polish

29. **`Working hours: no` footer reads as debug state.** Rephrase
    ("Outside working hours" / "Work window: closed" / "Next work
    window: Tomorrow 9:00 AM") and make it a clickable control that
    surfaces or edits the next window.

30. **Secondary-text contrast is too low.** Subtitles in the lists +
    overlay are nearly gray-on-light-gray. Productivity app — scan
    speed matters. Bump the contrast a notch.
