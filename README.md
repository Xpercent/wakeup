# WakeUp

An iOS alarm app that asks the user to complete 15 push-ups in the foreground camera before dismissing an alarm. It also provides a 20-digit emergency code for dismissal.

## Important iOS limitation

iOS does not permit an app to launch itself, force the camera UI on screen, prevent termination, or keep playing sound after the user force-quits it. WakeUp schedules a local alarm notification; opening the notification (or the app) activates the camera challenge. This is the maximum behavior available to a normal App Store-style iOS application.

## Build

Open `WakeUp.xcodeproj` in Xcode 15+ and run it on a physical iPhone. Camera and notification permissions are required. The included GitHub Actions workflow exports an unsigned IPA artifact; no signing profile is needed.
