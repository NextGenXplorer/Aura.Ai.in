# Branding assets

Place the AURA app logo here as:

    aura_logo.png   (square, 1024x1024 recommended, PNG)

This single image is the source for:
- Android launcher icon (all densities + adaptive icon)
- iOS app icon
- Web icons

After saving/replacing `aura_logo.png`, regenerate all icons with:

    dart run flutter_launcher_icons

The notification status-bar icon is a separate monochrome silhouette at
`android/app/src/main/res/drawable/ic_notification.xml` (Android renders small
status-bar icons as a single-colour mask, so a full-colour logo cannot be used
there). The full-colour logo is shown as the notification's large icon.
