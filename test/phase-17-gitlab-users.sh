MOCK_BIN=$MOCK_GITLAB_BIN
run_mock_phase test/gitlab-users.hurl -- backend=gitlab base_url=http://127.0.0.1:$MOCK_PORT
