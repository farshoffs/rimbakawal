# RimbaKawal iOS Push Preparation

The Flutter/Firebase Messaging client is already prepared to receive and deep-link push notifications, but APNs is intentionally **not activated yet** because an Apple Developer Program membership is required for production signing/capabilities.

When the Apple Developer Program account is ready:

1. Enable **Push Notifications** for the RimbaKawal App ID in Apple Developer.
2. Create an APNs Auth Key (`.p8`) or configure the appropriate APNs certificate.
3. Upload the APNs key/certificate to the RimbaKawal iOS app in Firebase Console.
4. Add the `aps-environment` entitlement to `mobile/ios/Runner.entitlements` while preserving the existing NFC entitlement. Use `mobile/ios/APNS_ENTITLEMENT_TEMPLATE.plist` only as a reference fragment.
5. Sign/provision the iOS build with a profile that includes Push Notifications and NFC.
6. Test foreground, background, and terminated-state notification opening on a physical iPhone.

Do not copy the template over `Runner.entitlements`; merge the APNs key into the existing entitlement file.
