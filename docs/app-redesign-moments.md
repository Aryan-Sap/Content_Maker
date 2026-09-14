# Studio interaction decisions

Profiles, library, editors, publishing and dialogs share one light ivory/white/green studio theme. The OS dark preference does not change the approved appearance. The actual video canvas retains its export colors; empty preview surfaces use the light inset. Both palettes are authored in StudioTheme, and compatibility Brand aliases now resolve to the approved light palette.

| Moment | Trigger | Visible commitment | Duration role | Haptic | Reduced motion |
|---|---|---|---|---|---|
| Press | Pointer down | Material pressed/focus state | Immediate | Silent | Same state |
| Workflow choice | Selection commits | Check mark, label, border | Quick | Silent | Instant |
| Create | Save succeeds | New row and editor opens | Reveal | Silent | Instant |
| Remove | Library write succeeds | Row removed, Undo available | Immediate | Silent | Same |
| Failure | Save/upload fails | Persistent message + next action | Immediate | Silent | Same |
| Upload | Provider reports progress | Per-channel status and percentage | Immediate | Silent | Same |
| Completion | Provider confirms result | Check + result link | Immediate | Silent | Same |
| Route | Navigate | Short vertical reveal | Reveal | Silent | No transition |

Desktop haptics are deliberately silent for every event. No celebration, looping ornament, sound, or input barrier. The media preview is content, not decorative animation. Entrances can be completed on pointer down and resolve immediately when the OS disables animation.
