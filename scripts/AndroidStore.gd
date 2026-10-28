extends RefCounted
## Where Android players get a new app binary. A Google Play build (export feature tag
## "play_store") must send players to its store listing, never to a side-loaded APK:
## Play forbids apps that update themselves outside Play.

const Localization = preload("res://scripts/Localization.gd")

const PACKAGE_NAME := "kr.ruellyya.catwar"
const PLAY_STORE_URL := "https://play.google.com/store/apps/details?id=" + PACKAGE_NAME

static func is_play_build() -> bool:
	return OS.has_feature("play_store")

static func binary_update_url(apk_url: String, play_build: bool) -> String:
	return PLAY_STORE_URL if play_build else apk_url

static func binary_update_button(play_build: bool) -> String:
	return Localization.text("스토어에서 업데이트") if play_build else Localization.text("APK 다운로드")

static func binary_update_message(play_build: bool) -> String:
	return Localization.text("앱 업데이트가 필요합니다.") if play_build else Localization.text("APK 업데이트가 필요합니다.")

static func binary_update_note(play_build: bool) -> String:
	return Localization.text("Play 스토어에서 업데이트한 뒤 게임을 다시 실행해 주세요.") if play_build else Localization.text("새 APK를 설치한 뒤 게임을 다시 실행해 주세요.")
