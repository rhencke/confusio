MOCK_BIN=$MOCK_PAGURE_BIN
run_mock_phase test/pagure-users.hurl -- backend=pagure base_url=http://127.0.0.1:$MOCK_PORT
