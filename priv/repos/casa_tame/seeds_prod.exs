# Production seeds for Casa Tame — accounts and categories only, no dummy data.
Ledgr.Repo.put_active_repo(Ledgr.Repos.CasaTame)

# Load core seeds (equity accounts)
Code.eval_file(Application.app_dir(:ledgr, "priv/repos/mr_munch_me/seeds/core_seeds.exs"))

# Load Casa Tame domain seeds (accounts + categories)
Code.eval_file(Application.app_dir(:ledgr, "priv/repos/casa_tame/seeds/casa_tame_seeds.exs"))
