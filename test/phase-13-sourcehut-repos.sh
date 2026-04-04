MOCK_BIN=$MOCK_SOURCEHUT_BIN
run_mock_phase test/sourcehut-repos.hurl -- backend=sourcehut base_url=http://127.0.0.1:$MOCK_PORT
