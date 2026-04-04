CONFUSIO_CONFIG="confusio = { backend=\"gitea\", base_url=\"http://127.0.0.1:$MOCK_PORT\" }"
run_mock_phase test/gitea-root.hurl
