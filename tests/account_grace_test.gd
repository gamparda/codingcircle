extends SceneTree
## Deletion grace: before DELETE_GRACE_FROM deleting is immediate; from then on a deleted account waits 30 days,
## comes back when the same Google account signs in (with a new nickname if the old one was taken), survives a
## restart, and is erased for good once the 30 days are over.

const AccountStore = preload("res://scripts/accounts/AccountStore.gd")

var failures := 0

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		printerr("FAIL: " + message)

func _store(now: int, directory: String = "") -> AccountStore:
	var store := AccountStore.new()
	store.now_override = now
	store.configure(directory)
	return store

func _init() -> void:
	var before := AccountStore.DELETE_GRACE_FROM - 3600
	var early := _store(before)
	var id: String = early.create("sub-a", "일찍지움", before).id
	check(early.delete(id) and early.withdrawn.is_empty() and early.restore("sub-a").is_empty(), "before the announced day deletion is immediate")
	check(early.create("sub-a", "새출발", before).has("id"), "and the Google account can start over")

	var after := AccountStore.DELETE_GRACE_FROM + 60
	var directory := "user://grace_test_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(directory)
	var store := _store(after, directory)
	var player: String = store.create("sub-b", "되돌림", after).id
	store.accounts[player].rating = 1450
	store.accounts[player].meta.gold = 777
	var token := store.issue_session(player, after)
	check(store.delete(player) and not store.accounts.has(player) and store.is_withdrawn(player), "from the announced day a deleted account waits")
	check(store.find_by_subject("sub-b").is_empty() and not store.nickname_taken("되돌림") and store.resume(token, after + 10).is_empty(), "while waiting it cannot sign in and its nickname is free")
	check(store.leaderboard(10).all(func(row): return String(row.nickname) != "되돌림"), "a waiting account is not on the leaderboard")
	store.flush()
	# Restart: the waiting account is still there.
	store = _store(after + 86400, directory)
	check(store.is_withdrawn(player), "the waiting account survives a restart")
	var back := store.restore("sub-b")
	check(back.get("id", "") == player and int(store.accounts[player].rating) == 1450 and int(store.accounts[player].meta.gold) == 777 and String(store.accounts[player].nickname) == "되돌림", "signing in again brings the same account back with its data")
	check(not store.is_withdrawn(player) and store.find_by_subject("sub-b") == player, "the restored account signs in normally")

	# Old nickname taken meanwhile: a new one is needed, then everything else returns.
	store.delete(player)
	var other: String = store.create("sub-c", "되돌림", after + 86400).id
	check(not other.is_empty() and store.restore("sub-b") == {"error": "nickname_taken"}, "a taken nickname asks for a new one")
	var created := store.create("sub-b", "되돌림2", after + 86400)
	check(created.get("id", "") == player and String(store.accounts[player].nickname) == "되돌림2" and int(store.accounts[player].meta.gold) == 777, "signing up again within the grace restores under the new nickname")

	# After 30 days the account is gone for good.
	store.delete(player)
	store.now_override = after + 86400 + AccountStore.DELETE_GRACE_SECONDS + 1
	check(store.restore("sub-b").is_empty(), "after 30 days nothing comes back")
	check(store.purge_withdrawn() == [player] and store.withdrawn.is_empty(), "the purge erases accounts past their grace")
	var fresh := store.create("sub-b", "완전새로", store.now_override)
	check(fresh.has("id") and fresh.id != player and int(store.accounts[fresh.id].meta.gold) == 0, "then the Google account starts from nothing")
	print("account_grace_test failures=%d" % failures)
	quit(1 if failures > 0 else 0)
