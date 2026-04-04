MOCK_BIN=$MOCK_GITBUCKET_BIN
run_mock_phase test/gitbucket-repos.hurl -- backend=gitbucket base_url=http://127.0.0.1:$MOCK_PORT
