extends RefCounted
## Elo ratings for ranked games. New accounts start at AccountStore.START_RATING; the first PROVISIONAL_GAMES
## games move the rating faster so new players reach their level sooner.

const K := 32
const K_PROVISIONAL := 48
const PROVISIONAL_GAMES := 10

static func expected(rating: int, opponent: int) -> float:
	return 1.0 / (1.0 + pow(10.0, float(opponent - rating) / 400.0))

## New rating after one game. `score` is 1 for a win, 0.5 for a draw and 0 for a loss.
static func updated(rating: int, opponent: int, score: float, games_played: int) -> int:
	var k := K_PROVISIONAL if games_played < PROVISIONAL_GAMES else K
	return maxi(1, rating + roundi(k * (score - expected(rating, opponent))))
