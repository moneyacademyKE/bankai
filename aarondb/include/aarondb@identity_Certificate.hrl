-record(certificate, {
    node :: binary(),
    fingerprint :: binary(),
    issuer :: binary(),
    state :: aarondb@identity:certificate_state()
}).
