MOCK_BIN=$MOCK_RADICLE_BIN
run_mock_phase test/radicle-repos.hurl -- backend=radicle base_url=http://127.0.0.1:$MOCK_PORT
