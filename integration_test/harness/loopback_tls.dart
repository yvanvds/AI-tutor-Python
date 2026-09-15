// A self-signed certificate for the loopback stand-in for GitHub (#124).
//
// This is what lets an end-to-end flow reproduce the production symptom:
// bind `FakeReleaseServer` with it and Dart's `HttpClient` fails the
// handshake with `CERTIFICATE_VERIFY_FAILED`, the same error a school's
// TLS-inspecting filter produces — BoringSSL cannot chain a certificate to
// anything in the Windows root store, and this one is in nobody's. The
// private key beside it is test material by design: nothing trusts this
// certificate, so nothing can be impersonated with it.
//
// Embedded as source rather than read from disk because an integration test
// runs inside the desktop app, whose working directory is not the checkout.
//
// Generated once with
//   openssl req -x509 -newkey rsa:2048 -nodes -days 36500 -subj /CN=localhost
//     -addext subjectAltName=DNS:localhost,IP:127.0.0.1
// and valid for a hundred years, so it does not have to be regenerated.

/// The certificate, PEM-encoded.
const String kLoopbackCertificatePem = '''
-----BEGIN CERTIFICATE-----
MIIDJzCCAg+gAwIBAgIUWGaJh6NjIEBVaUChvjNrx1CLbeEwDQYJKoZIhvcNAQEL
BQAwFDESMBAGA1UEAwwJbG9jYWxob3N0MCAXDTI2MDkxNTE3NTgwOVoYDzIxMjYw
ODIyMTc1ODA5WjAUMRIwEAYDVQQDDAlsb2NhbGhvc3QwggEiMA0GCSqGSIb3DQEB
AQUAA4IBDwAwggEKAoIBAQDLnmTSIX3sQ50lViUxtf2eO/q8c6cYKSRgueV1eOdG
xG60DHnrULJVnTrRi4hzkV24JXS5DW3pcZK8+KLOy1q7VNDrpUbWYPx84mWOlh/1
AoNIMcEXT9b9vGasLVnK8WdJvhngdEB91CCHsr996Jih4mEfiAgAtW8OZc72+jvd
EhgPbQZSwN15x3cQXPJxaOXsAzatpPqFU65p+qkCT9NuDEY2GWPDvubPmH+elzig
0X3lPyCwOYlDW/ANPdvf+CfL+AQ79m5qBtmRL1Gb840EfXjVND++ZPobm8bf0+sY
X5fNRy2NIXo3d8tfG7ZQasHPuVBpOyw8nz+PajH2xoKHAgMBAAGjbzBtMB0GA1Ud
DgQWBBTCtpbcHJAlpM6PcT0XxRaFyN2X4jAfBgNVHSMEGDAWgBTCtpbcHJAlpM6P
cT0XxRaFyN2X4jAPBgNVHRMBAf8EBTADAQH/MBoGA1UdEQQTMBGCCWxvY2FsaG9z
dIcEfwAAATANBgkqhkiG9w0BAQsFAAOCAQEABROLo4kVTOfKGb/ZntJpDEbuIkAo
tpKRX3cpVl6XrWDQOzrXEMRSbleF/u6ZT/tVtEGyFefKF4R0bj7dEK0Mc8YFJnsk
AKcQoK13yx75PoPsuPP8WOlvbfJ8UO4MOOh3RVBWLTxJSLmP3h15c+RNve603+A6
pMruErIi7CVouk5Lbsp6Zy4ZtTg1i3M0SbKN4gfbGHbAskZ0zyrbP685wc5QmVvR
ZY+6uAy0gwn6MznVMG47J6zjTe8Ra/eFXeC+omsj+lvvtNpeiX7WN060bueAlXFm
++7vdfkvZypUlWqamsxiB8D9kzVxSvD47NMit1BEi0IXp/W7bftfcWr0iQ==
-----END CERTIFICATE-----
''';

/// Its private key, PEM-encoded.
const String kLoopbackPrivateKeyPem = '''
-----BEGIN PRIVATE KEY-----
MIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwggSjAgEAAoIBAQDLnmTSIX3sQ50l
ViUxtf2eO/q8c6cYKSRgueV1eOdGxG60DHnrULJVnTrRi4hzkV24JXS5DW3pcZK8
+KLOy1q7VNDrpUbWYPx84mWOlh/1AoNIMcEXT9b9vGasLVnK8WdJvhngdEB91CCH
sr996Jih4mEfiAgAtW8OZc72+jvdEhgPbQZSwN15x3cQXPJxaOXsAzatpPqFU65p
+qkCT9NuDEY2GWPDvubPmH+elzig0X3lPyCwOYlDW/ANPdvf+CfL+AQ79m5qBtmR
L1Gb840EfXjVND++ZPobm8bf0+sYX5fNRy2NIXo3d8tfG7ZQasHPuVBpOyw8nz+P
ajH2xoKHAgMBAAECggEAAKohYYKX37iixfeF6Vq5aEka1H86769Z5CTtlLISn/g0
W+SuIZbJIwVl2gw7o3qGFOIU0CVoLLrHRCDUBM4q6CSeBlh32dHfarFUeOz3HFYb
Q2LCL62XiCStLLYWYaN8qlCmbF8Ew0RfeZuB2EsOwHlPYHDehQR4+p7APuC3NE2a
0w6Z8/xys6LlmOFb6XoMiFj/uZDdPNS4Lgu11ogKsqi6tog5eW9IN0P5RgBjJQVZ
iPIZbxjAF6NjYUM1bb9iT99ZglX/A4ykV1yLW3HV6ZvRRN7r7enaIpMv0VtqDqtx
lT3A5lGcanoFbDnfCshaQPaqpJ4eNDG3J21rSoaLMQKBgQDp4Z0Kn8o2m8fmJbJN
1v5N8BwxX8ZQXh9U9JSh/ZFeeVeEEYJ47RywZfJeqFCQmPBJ64JgyJULJP2APvZ6
dLkCh93XLCWy/Vt8/rBhIXuUfyzYFYBC93iSPKgeEfMHQEPr/srItrJF06wcny2x
nrjwxjM6GOZOM3elyrQABjr7cQKBgQDe4BucNS0fKpi4FHzvAKvtzNRiGZTvsbph
ZjXvRYQi+PtneFJzkG6wT89fWJT+MS1BBr3Z4XAVxP1aUmvk4dYc8LrPuh3eE+sL
Ly1LNeY/zF7G8QX4L+gopXpuG4OFUIHRC7gvnLweYhNfdrEEv9LOJUQDyC4Qhurd
N8IkH2sxdwKBgQCiZZgnwmAknvKkqdQvHHOkJm9NEVWghFp5IQL7oBgKY3MTLx1L
XkknawJqG7ElViyzByaWkXB8NokXPaDj0pyMV08Ak5Txvd6C4k4Sg69Noyi+Od+/
oBpGYHvTtV7s0ADZoyenSsRqm9nMXfLafH2qIdV8J8Hy1uXjZuaphan64QKBgAU+
dKfaQHOJRwqdwMrG00THGwAr5es13VLJWt+EXTWNcizfEeGSNmiDmDeAGBFbCtuK
0xC7Uy3P8r4bTlqWTblkmKCmmmlNQqyCsaghXoeFwX0g0qkiR24dZqIMl62dVVCb
2/uSzoJQgHAwlL2t3cHn8o+8OAk/g2stEq5S5uzFAoGAEGBGyMtDYjsa/nfTfhut
Gbx1AUn2jfa+kD9mm3MyVyX/VS7Ujvn4XhSlvKaxOCQm1rBL7r3LLE9+Db9piT6P
kkdop0E7CgMwl5D/FMMc0W17Uf3vf18IyBiMtGol+gU0fxwaTSoFYEEARxpXEooG
5GtUka7RjwsvzylF/zN62xw=
-----END PRIVATE KEY-----
''';
