import SwiftUI

/// In-app Help window (Help → "Moves Help", Cm­d-?). A single
/// vertically-scrolling page that teaches the product vocabulary from
/// INITIAL-PLAN.md — thread, item, capture, breadcrumb, deadline, parking,
/// working hours — and states what Moves explicitly is NOT.
///
/// Deliberately not a `TabView`: this is a teaching page, not a
/// configuration UI. The reader should be able to scroll once and have the
/// model in their head. Sections are short (1–3 paragraphs), the column is
/// constrained to ~560pt for readability, and headings step down through
/// the semantic type scale so the visual hierarchy survives a Dynamic Type
/// override.
///
/// Hosted as its own `Window` scene (see `MovesApp`) keyed by
/// `PopoverWindowID.help`. The menubar popover would auto-dismiss any
/// SwiftUI `.sheet` on focus loss, so help — like the Phase-3 flow
/// sheets — gets a real window.
struct HelpView: View {
  /// Constrains line length to a comfortable reading measure. ~560pt at
  /// the default body size lands around 70–75 characters per line, which
  /// is the upper end of the typographic sweet spot for prose. Wider than
  /// this and the eye loses the line break.
  private let columnWidth: CGFloat = 560

  /// Vertical rhythm between sections. ~24pt is roughly 1.5× body line
  /// height, enough to clearly separate sections without making the page
  /// feel like a list of cards.
  private let sectionSpacing: CGFloat = 24

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: sectionSpacing) {
        title
        section("What is Moves?") {
          paragraph("""
          A passive macOS menu-bar app that helps you stop wasting time \
          by quickly resuming one important thread of work — while also \
          handling lightweight reminders and deadlines without turning \
          into a generic GTD system.
          """)
          paragraph("""
          Moves is built around re-entry, not inventory. The question \
          it answers is "what was I working on, and what's the next \
          move?" — not "what tasks are due today?" The menu bar is the \
          surface; the main window is for occasional housekeeping.
          """)
        }

        section("Threads") {
          paragraph("""
          A thread is a stream of work you're trying to resume. It's the \
          central concept in Moves and the unit of "what am I working \
          on." Projects, ongoing efforts, recurring practice, a chapter \
          you're writing — all threads.
          """)
          paragraph("""
          A thread is active, parked, or done. Each thread carries a \
          breadcrumb (the next move), optional open items, and an \
          optional segment when the work is regimented. Threads are \
          flat: no folders, no tags, no nesting. The whole product is \
          organized around picking one up and putting one down.
          """)
        }

        section("Items: captures, tasks, reminders") {
          paragraph("""
          An item is something captured. There are three kinds, \
          distinguished by how urgently they want your attention.
          """)
          paragraph("""
          A **capture** is a quick, undated note — the inbox. You jotted \
          it down so you wouldn't forget; the app won't bother you about \
          it. A **task** has a soft due time: it's expected by then, but \
          it won't interrupt you. A **reminder** has a hard due time and \
          will fire a system notification — the only kind of item that \
          actively interrupts.
          """)
          aside("""
          The difference is alert policy, not importance. A capture can \
          become a reminder later by setting a hard deadline.
          """)
        }

        section("The capture hotkey") {
          paragraph("""
          ⌥Space opens a Spotlight-style capture field from anywhere. \
          Type a line, hit Return, it's saved. Use it for anything you \
          don't want to lose track of — a thought, a chore, a phone \
          call to make in twenty minutes.
          """)
          paragraph("""
          Captures save without a deadline by default. The parser \
          recognizes time phrases at the end of the line — "call Sarah \
          in 18m", "pull rice at 5pm", "ship draft Friday 5pm" — and \
          promotes the item to a task or reminder accordingly. The \
          grammar is deterministic; there's no LLM guessing what you \
          meant.
          """)
        }

        section("Current vs Available") {
          paragraph("""
          **Current** is the one thread you're actively on right now. \
          There is zero or one — never two. **Available** is the set of \
          threads you could pick up next: active threads with a real \
          re-entry point.
          """)
          paragraph("""
          You move between them with three flows. **Stop** ends the \
          current segment without picking a new thread. **Switch** ends \
          it and immediately starts another. **Park** sets a thread \
          aside without abandoning it. Each flow prompts for a \
          breadcrumb, because the next time you come back, you'll want \
          to know where you left off.
          """)
        }

        section("Breadcrumbs") {
          paragraph("""
          A breadcrumb is the explicit "next move" note attached to a \
          thread. It's the re-entry signal — the sentence you read \
          tomorrow morning that lets you start working in seconds \
          instead of spending ten minutes reconstructing context.
          """)
          paragraph("""
          Breadcrumbs are the killer feature. A thread without a \
          breadcrumb (and without open items or an active segment) has \
          no re-entry point, so it drops out of Available. This is the \
          core invariant: Available means "I know how to resume this." \
          Write a breadcrumb when you stop, switch, or park.
          """)
        }

        section("Deadlines") {
          paragraph("""
          Deadlines are the only urgency signal in Moves. There are no \
          priority levels, no flags, no stars. If something matters \
          enough to surface, it has a time on it.
          """)
          paragraph("""
          **Hard** deadlines fire system notifications and badge the \
          menu-bar icon. **Soft** deadlines are passive aids: they sort \
          and surface things in the Upcoming section, but they won't \
          interrupt you. Use hard sparingly — the value of a hard \
          deadline is that it's rare enough to mean something.
          """)
        }

        section("Working hours") {
          paragraph("""
          Working hours are a visibility filter, not an enforcement \
          mechanism. The app doesn't lock you out of personal threads \
          during the workday, or vice versa. It just de-emphasizes the \
          things that don't belong to the current period.
          """)
          paragraph("""
          De-emphasized panes don't disappear; they sit quieter. A \
          deadline-bearing item still surfaces no matter what hours \
          you're in. The intent is to reduce friction in the common \
          case, not to discipline you.
          """)
        }

        section("Importing regimented threads") {
          paragraph("""
          A regimented thread is one where the work is laid out in \
          ordered segments — a study plan, a course curriculum, a \
          training program. You can build one from scratch inside the \
          app, but for anything longer than a few segments it's faster \
          to write the whole plan in a Markdown file and import it via \
          **Import Markdown…** in the sidebar footer.
          """)
          paragraph("""
          The grammar is deterministic. A YAML frontmatter block sets \
          the thread-level metadata; each `## ` heading starts a \
          segment; `- [ ] / - [x]` checkboxes become items; anything \
          else becomes the segment's body Markdown. No LLM guesswork.
          """)

          subheading("Thread frontmatter")
          paragraph("""
          Wrap the frontmatter in `---` on its own line, top and bottom. \
          Supported keys:
          """)
          codeBlock("""
          ---
          title: Python Refresh
          kind: regimented
          visibility: normal
          default_estimate_minutes: 60
          ---
          """)
          paragraph("""
          `title` is the only required key; everything else defaults. \
          `kind` accepts `regimented` (the typical case) or `normal`. \
          `visibility` accepts `always`, `normal`, `hide_during_work`, \
          or `only_during_work` — the same options the per-thread \
          visibility pill shows. `default_estimate_minutes` is the \
          fallback estimate for any segment that doesn't set its own.
          """)

          subheading("Segment headings + metadata")
          paragraph("""
          Each segment starts with a `## ` H2. The lines that follow \
          (before the first checkbox or blank-line-then-body) can carry \
          per-segment metadata as `key: value` lines:
          """)
          codeBlock("""
          ## Day 01: Modern Python syntax
          date: 2026-06-01
          due: 2026-06-12 17:00
          estimate: 60
          move: Write a tiny parser using dataclasses and match/case.
          """)
          paragraph("""
          `move` is the segment's built-in "next move" — what shows up \
          in Available when this segment is active. `date` is a planned \
          start (informational only). `due` is the deadline if any — \
          accepts `YYYY-MM-DD` for a date or `YYYY-MM-DD HH:MM` for a \
          datetime. `estimate` is rough minutes; it overrides the \
          thread's `default_estimate_minutes`.
          """)

          subheading("Items and body")
          paragraph("""
          Markdown checkboxes inside a segment become tracked items:
          """)
          codeBlock("""
          - [ ] Review dataclasses
          - [ ] Review type hints
          - [x] Write parser
          - [ ] Add pytest cases
          """)
          paragraph("""
          `- [x]` lands as a completed item, `- [ ]` as open. Any \
          remaining Markdown after the metadata block and not in a \
          checkbox becomes the segment's body — paragraphs, sub-lists, \
          links, fenced code blocks all survive.
          """)

          subheading("Ordering and import semantics")
          paragraph("""
          Segment order is file order. The first segment becomes \
          **active** on import; the rest stay **pending**. Importing \
          the same file twice creates two distinct threads — v1 is \
          create-only, not update-in-place. The importer surfaces a \
          warning in the preview when it sees a duplicate title so \
          you can cancel before committing.
          """)
          aside("""
          A complete example lives in `INITIAL-PLAN.md §9` if you want \
          a longer reference.
          """)
        }

        section("What Moves is NOT") {
          paragraph("""
          Moves is deliberately opinionated about what it leaves out. \
          The omissions are the product.
          """)
          paragraph("""
          **No priority levels.** Deadlines are the only urgency \
          signal — no low/medium/high theatre. **No tags, areas, or \
          nested hierarchy.** The model is Thread, Segment, Item; \
          that's it. **No streaks, scores, or idle detection.** Moves \
          is passive, not disciplinary. **No precise time tracking.** \
          Rough buckets only — 15m, 30m, 1h, a few hours. **No LLM.** \
          The capture parser and Markdown importer are deterministic; \
          you can predict exactly what they'll do.
          """)
          aside("""
          If you find yourself wanting one of these, that's usually a \
          sign the work belongs in a different tool.
          """)
        }
      }
      .frame(maxWidth: columnWidth, alignment: .leading)
      .padding(.horizontal, 32)
      .padding(.vertical, 28)
      .frame(maxWidth: .infinity, alignment: .center)
    }
    .background(.background)
    .navigationTitle("Moves Help")
  }

  // MARK: - Building blocks

  /// The page title. One step above section headings so the eye lands here
  /// first when the window opens. Bold weight + `.title` is the standard
  /// macOS document-title rendering.
  private var title: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("Moves Help")
        .font(.title)
        .fontWeight(.bold)
      Text("How to think about threads, items, and re-entry.")
        .font(.callout)
        .foregroundStyle(.secondary)
    }
    .padding(.bottom, 4)
  }

  /// A section: heading + content. `.title3` semibold matches the
  /// Onboarding sheet's section heading style so the in-app type system
  /// stays consistent.
  @ViewBuilder
  private func section<Content: View>(
    _ heading: String,
    @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(heading)
        .font(.title3)
        .fontWeight(.semibold)
        .foregroundStyle(.primary)
      content()
    }
  }

  /// Body paragraph. `LocalizedStringKey` here is what lets Markdown
  /// emphasis (`**bold**`) render inline without us reaching for
  /// `AttributedString`.
  private func paragraph(_ text: LocalizedStringKey) -> some View {
    Text(text)
      .font(.body)
      .foregroundStyle(.primary)
      .fixedSize(horizontal: false, vertical: true)
  }

  /// A subdued aside. Smaller, secondary, used for the "by the way" notes
  /// inside a section — clarifications that aren't part of the main
  /// teaching beat.
  private func aside(_ text: LocalizedStringKey) -> some View {
    Text(text)
      .font(.callout)
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)
  }

  /// A second-level heading inside a section. Used by the "Importing
  /// regimented threads" section where the surface is large enough to
  /// benefit from internal structure. `.headline` semibold sits one step
  /// below the section heading so the page hierarchy stays readable
  /// without the eye losing the section boundary.
  private func subheading(_ text: String) -> some View {
    Text(text)
      .font(.headline)
      .foregroundStyle(.primary)
      .padding(.top, 4)
  }

  /// A fenced code-block style. Monospaced text on a subtle filled
  /// background, full column width — same idiom as the popover's segment
  /// code rendering. Preserves leading whitespace so YAML / Markdown
  /// examples read cleanly.
  private func codeBlock(_ text: String) -> some View {
    Text(text)
      .font(.system(.callout, design: .monospaced))
      .foregroundStyle(.primary)
      .textSelection(.enabled)
      .padding(10)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        RoundedRectangle(cornerRadius: 6, style: .continuous)
          .fill(Color(nsColor: .textBackgroundColor))
      )
      .overlay(
        RoundedRectangle(cornerRadius: 6, style: .continuous)
          .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
      )
  }
}

#Preview {
  HelpView()
    .frame(width: 600, height: 700)
}
