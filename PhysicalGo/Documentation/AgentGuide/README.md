# Physical Go: start here

This guide explains the project for a new chat or a human reader. Read only the
pages relevant to the task; the source links are entry points, not an exhaustive
file inventory. Prepared November 22, 2026 from inspected code, repository
documentation, shared laser handoffs and the current integration conversation.
No tool for reading other historical chats was available. Historical claims are
therefore grounded in the durable project records, not a purported review of all
past conversations.

**Read the [current integration checklist](../IntegrationChecklist.md) before
acting.** It owns current implementation, validation, installation and hardware
state. This guide owns architecture and reading routes. A source change, passing
offline test, installed binary and successful physical test are four different
facts.

## Resume in five minutes

1. Read the application [AGENTS.md](../../../AGENTS.md) and the checklist's current
   checkpoint and immediate next steps. Preserve game history, clocks and
   calibration; do not infer current hardware state from an old chat.
2. Inspect both repositories' branch, status and recent commits. Check the
   installed app/firmware separately. At this guide's preparation checkpoint,
   installed Physical Go was 0.252 and firmware v39; schema-2 monitored holding
   and v44 were being developed. Those are dated facts, not a standing claim
   about the current installation.
3. For laser work, read the latest shared outgoing and incoming handoff files.
   A request is not an active dependency until the other agent acknowledges it.
4. Select a page from the table below. Follow its source links and targeted
   regression suite before changing the relevant subsystem.
5. Before physical work, establish the current hardware owner and verify the
   moved setup/calibration. The root integration chat is the sole hardware owner
   unless ownership is explicitly transferred. Other agents work offline.

| Immediate concern | Read |
|---|---|
| Where decisions live; how components connect | [Architecture and state ownership](Architecture.md) |
| Structural weaknesses and incremental improvement priorities | [Independent architecture/process review](../ArchitectureReview.md) |
| Wrong camera, hand not clearing, missed stone, glare, stale image | [Camera and recognition](CameraRecognition.md) |
| AI speed, legal moves, turn transitions, clocks, saved games | [Game, AI and clocks](GameAIClocks.md) |
| Local recording, unresolved chronology, corrections, scoring | [Recording, review and scoring](RecordingReviewScoring.md) |
| Laser doesn't appear, holding/cooling, firmware, calibration | [Laser control and calibration](LaserControlCalibration.md) |
| Ambiguous stone, captured stone, wrong/illegal placement | [Markers and physical corrections](Markers.md) |
| Build, targeted tests, source hash, repository workflow | [Development and validation](DevelopmentValidation.md) |
| A specific failure or unresolved investigation | [Troubleshooting and known problems](Troubleshooting.md) |

## Repositories and durable records

| Location | Responsibility |
|---|---|
| `/Users/dave/SGFPlayerClean` · [GitHub](https://github.com/davemarvit/SGFPlayerClean) | Native macOS applications, Go model/engine, camera recognition, game decisions and app-side bridge. Physical Go lives under `PhysicalGo/`. |
| `/Users/dave/Personal/Fab Files/DYNAMIXEL Go Pointer` · [private GitHub](https://github.com/davemarvit/DYNAMIXEL-Go-Pointer) | Pointer firmware, Python hardware bridge, optical setup, host/native tests, mechanical design and assembly records. |
| [IntegrationChecklist.md](../IntegrationChecklist.md) | Current work list, accepted behavior, latest installed/physical checkpoint. |
| [LivePositionIssues.md](../LivePositionIssues.md) | Numbered problem cases and chronological investigation/validation record. Later entries can supersede earlier conclusions. |
| [Shared outgoing handoff](</Users/dave/Personal/Fab Files/DYNAMIXEL Go Pointer/Firmware/AI play integration reply.txt>) / [incoming handoff](</Users/dave/Personal/Fab Files/DYNAMIXEL Go Pointer/Firmware/AI play integration response.txt>) | Cross-chat coordination. Check dates and explicit ownership acknowledgements. |

The pre-holding checkpoints were app `e8b2b14` and laser `1060bef`, both pushed.
Development then moved to `codex/monitored-gameplay-holding` in both repositories.
Use Git to inspect what followed; do not reset a later working tree to these
checkpoints merely to match this guide.

## A useful new-chat prompt

> Continue Physical Go work in `/Users/dave/SGFPlayerClean` and the laser project
> in `/Users/dave/Personal/Fab Files/DYNAMIXEL Go Pointer`. Read both AGENTS.md
> files, `PhysicalGo/Documentation/AgentGuide/README.md`, the current integration
> checklist and latest shared handoffs. My immediate task is **[specific task]**.
> Inspect current branches and installed/runtime state before acting. Preserve
> game/clocks/calibration and coordinate exclusive hardware ownership. Distinguish
> implementation, offline tests, installation and physical validation in the result.

Add the user's current readiness and physical changes to that prompt. An old
authorization or old camera/laser photograph is not evidence that equipment has
remained in the same place.

## Maintaining this guide

Update the relevant page when responsibility, a contract or a source entry point
changes. Put current task status in the checklist and incident evidence in
LivePositionIssues. Link detailed protocol/test plans instead of copying their
full contents. Keep proposed features labelled as proposals until implementation
and validation are recorded.
