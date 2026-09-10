# Orbit 0.6.0 — local announcement drafts

Not posted or saved to a social account. Publication is gated on validation, user
acceptance, GitHub release, actual marketplace publication and final wording approval.
Replace `[MARKETPLACE_URL]` only with the verified canonical listing for the published
0.6.0 snapshot. Do not announce availability while a submission is pending.

## X

Drag. Choose. Drop.

Orbit 0.6 brings Windows-inspired snap layouts to Omarchy: pick a zone before letting
go, or go Maximized/Fullscreen. Plus multi-monitor Alt-Tab.

Live dragging needs the native bridge.

[MARKETPLACE_URL]

The text remains below 280 characters with a normal shortened X link. Recheck the
final composition after inserting the link or changing wording. Say Windows-inspired,
not an identical Windows 11 implementation.

Suggested later demo: a clean temporary window, drag to top, hover the live picker,
release into a half, then demonstrate Maximized. About 10–15 seconds, muted; no personal
tabs, chats, notifications or account data. This is a storyboard, not a recorded or
verified attachment. Record and review separately before attaching anything public.

## r/developersIndia — engineering draft to personalize

Suggested title: **Windows-inspired snapping on Hyprland: showing the picker during a drag**

I wanted familiar window switching and snapping on my Omarchy desktop. Orbit's next
update adds a live layout picker: drag to the top or a corner, choose a zone while
holding the button, then release. It also includes separate Maximized and Fullscreen
choices and multi-monitor Alt-Tab.

The interesting part is the compositor interaction. A release-only hook cannot show
the picker during the drag, and a focus-grabbing overlay can interrupt the move. The
implementation uses a small C++ Hyprland bridge and a passive QML/Quickshell overlay;
the drop is applied after Hyprland's own drag-end processing.

The tradeoff is compatibility: the native bridge must match the installed Hyprland
ABI and be rebuilt after upgrades. This has been an AI-assisted project; before posting
I want to share the actual validation results and the limitations, not claim Windows
parity.

Source: [Orbit on GitHub](https://github.com/rohan-patnaik/orbit). Add the accepted
release link here only after it exists.

Owner review: replace the final paragraph's pre-publication wording with your own
account of what you tested and learned. Add one concrete firsthand observation. This
is a writing aid, **not text to paste automatically into Reddit**. Keep it technical;
avoid install/star requests or claims that every video platform passed. Choose the
appropriate showcase flair after rechecking current rules.

The community's [showcase guidance](https://www.reddit.com/r/developersIndia/comments/1ca5bn4/how_to_create_a_perfect_i_made_this_post_on/)
asks for context, project links and preferably a demo. Its more recent
[moderator direction](https://www.reddit.com/r/developersIndia/comments/1vd8a6j/a_quick_note_regarding_the_direction_of/)
emphasizes engineering knowledge-sharing and discourages copy-pasted AI posts and
recruitment-style promotion. Moderation is not guaranteed; recheck before submission.
