const regions = [
  { min: 1, max: 10, key: 'dungeon', name: '무너진 던전', bg: '탑 내부 던전', mob: '고블린', boss: '던전 골렘', tablet: '탑은 감옥이 아니다. 탑은 문이다.', story: '탑 내부는 오래된 지하 감옥처럼 차갑다. 고블린들이 폐허를 점령하고 있다.' },
  { min: 11, max: 20, key: 'forest', name: '뒤틀린 숲', bg: '숲', mob: '늑구', boss: '붉은 눈의 알파늑대', tablet: '아르카론은 하늘을 열었고, 하늘 너머의 것이 그들을 내려다보았다.', story: '해도 달도 없는데 나무는 자라고, 바람이 없는데 잎은 흔들린다.' },
  { min: 21, max: 30, key: 'beach', name: '저주받은 해변', bg: '해변', mob: '소라게', boss: '심해 메갈로돈', tablet: '그들은 별을 연구하지 않았다. 별에게 먹이를 주었다.', story: '파도는 밀려오지만 물러가지 않는다. 소라게들은 탑의 파편을 짊어지고 있다.' },
  { min: 31, max: 40, key: 'desert', name: '죽음의 사막', bg: '사막', mob: '미라', boss: '데스웜', tablet: '문을 닫기 위해, 그들은 살아 있는 도시를 제물로 삼았다.', story: '태양이 셋 떠 있고, 모래 아래에는 이름 없는 자들의 무덤이 이어진다.' },
  { min: 41, max: 50, key: 'snow', name: '얼어붙은 설원', bg: '얼어붙은 설원', mob: '설원 엘프', boss: '예티', tablet: '봉인은 실패하지 않았다. 다만 너무 오래 버텼을 뿐이다.', story: '눈은 계속 내리지만 쌓이지 않는다. 설원 엘프들은 얼어붙은 기억처럼 움직인다.' },
  { min: 51, max: 60, key: 'volcano', name: '화산지대', bg: '화산지대', mob: '마그마골렘', boss: '용암 드래곤', tablet: '탑의 핵은 봉인 장치이자 심장이다. 심장이 뛰는 한, 문도 닫힌다.', story: '탑이 적의를 드러낸다. 이곳부터는 반복 사냥과 장비 강화가 필요하다.' },
  { min: 61, max: 70, key: 'rift', name: '차원의 틈새', bg: '차원의 틈새', mob: '마법사', boss: '검은 마법사', tablet: '핵을 부수면 세상은 산다. 그러나 문도 열린다.', story: '계단은 위로 올라가면서 아래로 떨어지고, 문은 기억에 따라 다른 곳으로 열린다.' },
  { min: 71, max: 80, key: 'hell', name: '지옥', bg: '지옥', mob: '악마', boss: '마왕 바알', tablet: '너는 위로 올라간다고 믿지만, 사실은 문 앞으로 끌려가고 있다.', story: '불타는 지옥은 진짜 사후세계가 아니라 탑이 흉내 낸 실패한 차원이다.' },
  { min: 81, max: 90, key: 'heaven', name: '천국', bg: '천국', mob: '천사', boss: '대천사', tablet: '선은 언제나 생명을 구하지 않는다. 때로는 안전이라는 이름으로 죽음을 고른다.', story: '눈부신 빛은 따뜻하지 않다. 천사들은 구원이 아니라 정지를 말한다.' },
  { min: 91, max: 100, key: 'ender', name: '엔더', bg: '엔더', mob: '심연 덩어리', boss: '엔더 드래곤', tablet: '우리는 괴물을 가둔 것이 아니다. 괴물이 들어오지 못하도록 세상을 가둔 것이다.', story: '검은 별빛이 바닥처럼 깔려 있다. 모든 지역의 기억이 심연 속에서 뒤섞인다.' }
];

const enemyArt = {
  '고블린': 'assets/monsters/goblin.png',
  '던전 골렘': 'assets/monsters/dungeon-golem.png',
  '늑구': 'assets/monsters/wolfgu.png',
  '붉은 눈의 알파늑대': 'assets/monsters/red-alpha-wolf.png',
  '마법사': 'assets/monsters/dark-summoner.png',
  '검은 마법사': 'assets/monsters/black-wizard.png',
  '심연 덩어리': ['assets/monsters/abyss-mass.png', 'assets/monsters/teal-abyss-golem.png'],
  '엔더 드래곤': 'assets/monsters/ender-dragon.png'
};

const weapons = [
  { name: '한손검', attack: 13, speed: 12, block: 30, skill: '균형 베기', desc: '안정적인 공격. 막기 30%.' },
  { name: '쌍검', attack: 10, speed: 18, block: 40, skill: '연속 베기', desc: '낮은 공격력, 빠른 공속. 막기 40%.' },
  { name: '대검', attack: 18, speed: 6, block: 25, skill: '강타', desc: '높은 공격력, 느린 공속. 막기 25%.' },
  { name: '마법 지팡이', attack: 17, speed: 11, block: 0, skill: '보호막', desc: '막기 없음. 보호막으로 다음 피해 60% 감소.' },
  { name: '활', attack: 12, speed: 99, block: 0, skill: '관통 사격', desc: '확정 선공권. 막기 없음.' }
];

const el = Object.fromEntries([
  'regionBadge', 'scene', 'monsterCard', 'enemyType', 'enemyName', 'enemyHpText', 'enemyHpBar', 'storyTitle', 'storyText',
  'floorText', 'playerTitle', 'weaponText', 'playerHpText', 'playerHpBar', 'attackText', 'speedText', 'blockText',
  'goldText', 'actions', 'choicePanel', 'log', 'progressText', 'attackButton', 'skillButton', 'potionButton', 'resetButton'
].map(id => [id, document.getElementById(id)]));

let state;

function newGame() {
  state = {
    floor: 1,
    maxHp: 100,
    hp: 100,
    baseAttack: 8,
    baseSpeed: 8,
    weapon: { name: '초보자 방망이', attack: 8, speed: 8, block: 10, skill: '힘껏 치기', desc: '임시 초보 무기.' },
    gold: 0,
    potions: 2,
    shield: false,
    enemy: null,
    locked: false,
    gameOver: false,
    weaponChosen: false
  };
  el.log.innerHTML = '';
  log('검은 별빛을 멈추기 위해 탑에 들어섰다.', 'important');
  spawnEnemy();
  render();
}

function regionForFloor(floor) {
  return regions.find(r => floor >= r.min && floor <= r.max) || regions[regions.length - 1];
}

function isBossFloor(floor) {
  return floor % 10 === 0;
}

function createEnemy() {
  const region = regionForFloor(state.floor);
  const boss = isBossFloor(state.floor);
  const tier = Math.ceil(state.floor / 10);
  const hp = Math.round((boss ? 48 : 22) + state.floor * (boss ? 7.5 : 3.4));
  const attack = Math.round((boss ? 11 : 6) + state.floor * (boss ? 1.15 : 0.62));
  const speed = Math.round((boss ? 7 : 5) + tier * 1.6 + (boss ? 1 : 0));
  return {
    name: boss ? region.boss : region.mob,
    type: boss ? '보스' : '잡몹',
    maxHp: hp,
    hp,
    attack,
    speed,
    boss
  };
}

function spawnEnemy() {
  state.enemy = createEnemy();
  const region = regionForFloor(state.floor);
  if (state.floor === region.min) log(`${region.name}에 진입했다. ${region.story}`, 'important');
  if (state.enemy.boss) log(`${state.floor}층 보스 ${state.enemy.name}이 길을 막는다.`, 'danger');
}

function playerAttackPower(multiplier = 1) {
  const variance = randomInt(-2, 3);
  return Math.max(1, Math.round((state.baseAttack + state.weapon.attack + variance) * multiplier));
}

function enemyAttackPower() {
  const variance = randomInt(-2, 3);
  return Math.max(1, state.enemy.attack + variance);
}

function attack() {
  if (state.locked || state.gameOver) return;
  runTurn('attack');
}

function skill() {
  if (state.locked || state.gameOver) return;
  runTurn('skill');
}

function usePotion() {
  if (state.locked || state.gameOver) return;
  if (state.potions <= 0) {
    log('포션이 없다.', 'danger');
    return;
  }
  state.potions -= 1;
  const heal = Math.round(state.maxHp * 0.36);
  state.hp = Math.min(state.maxHp, state.hp + heal);
  log(`포션을 마셨다. HP ${heal} 회복. 남은 포션 ${state.potions}개.`, 'good');
  enemyAction();
  checkLose();
  render();
}

function runTurn(kind) {
  const playerFirst = state.weapon.speed >= state.enemy.speed || state.weapon.name === '활';
  if (playerFirst) {
    playerAction(kind);
    if (checkWin()) return;
    enemyAction();
    checkLose();
  } else {
    enemyAction();
    if (checkLose()) return;
    playerAction(kind);
    checkWin();
  }
  render();
}

function playerAction(kind) {
  if (kind === 'skill') {
    if (state.weapon.name === '마법 지팡이') {
      state.shield = true;
      const damage = playerAttackPower(0.65);
      state.enemy.hp = Math.max(0, state.enemy.hp - damage);
      log(`보호막을 펼치고 마력탄을 날렸다. ${state.enemy.name}에게 ${damage} 피해.`, 'good');
      return;
    }
    const multiplier = state.weapon.name === '쌍검' ? 1.35 : state.weapon.name === '대검' ? 1.75 : state.weapon.name === '활' ? 1.45 : 1.5;
    const damage = playerAttackPower(multiplier);
    state.enemy.hp = Math.max(0, state.enemy.hp - damage);
    log(`${state.weapon.skill}! ${state.enemy.name}에게 ${damage} 피해.`, 'good');
    return;
  }

  const damage = playerAttackPower(1);
  state.enemy.hp = Math.max(0, state.enemy.hp - damage);
  log(`${state.enemy.name}을 공격했다. ${damage} 피해.`);
}

function enemyAction() {
  if (state.enemy.hp <= 0) return;
  let damage = enemyAttackPower();

  if (state.shield) {
    damage = Math.ceil(damage * 0.4);
    state.shield = false;
    state.hp = Math.max(0, state.hp - damage);
    log(`보호막이 피해를 줄였다. ${damage} 피해만 받았다.`);
    return;
  }

  if (Math.random() * 100 < state.weapon.block) {
    const reduced = Math.ceil(damage * 0.35);
    state.hp = Math.max(0, state.hp - reduced);
    log(`막기에 성공했다. ${reduced} 피해만 받았다.`);
    return;
  }

  state.hp = Math.max(0, state.hp - damage);
  log(`${state.enemy.name}의 반격. ${damage} 피해.`, 'danger');
}

function checkWin() {
  if (state.enemy.hp > 0) {
    render();
    return false;
  }

  const reward = state.enemy.boss ? 45 + state.floor * 4 : 12 + state.floor * 2;
  state.gold += reward;
  log(`${state.enemy.name} 처치! ${reward}골드 획득.`, 'good');

  if (state.enemy.boss) {
    const region = regionForFloor(state.floor);
    log(`석판: “${region.tablet}”`, 'important');
  }

  if (state.floor >= 100) {
    ending();
    return true;
  }

  state.floor += 1;
  state.baseAttack += state.floor % 3 === 0 ? 1 : 0;
  state.baseSpeed += state.floor % 7 === 0 ? 1 : 0;
  state.maxHp += state.floor % 4 === 0 ? 5 : 0;
  state.hp = Math.min(state.maxHp, state.hp + Math.round(state.maxHp * 0.18));

  if (state.floor === 6 && !state.weaponChosen) {
    showWeaponChoice();
    render();
    return true;
  }

  if (shouldShowShop()) {
    showShop();
    render();
    return true;
  }

  spawnEnemy();
  render();
  return true;
}

function checkLose() {
  if (state.hp > 0) return false;
  state.gameOver = true;
  log('쓰러졌다. 탑은 다시 조용해졌다.', 'danger');
  el.actions.querySelectorAll('button').forEach(btn => btn.disabled = true);
  render();
  return true;
}

function shouldShowShop() {
  const prev = state.floor - 1;
  const local = ((prev - 1) % 10) + 1;
  return local === 5 || local === 9;
}

function showWeaponChoice() {
  state.locked = true;
  el.choicePanel.classList.remove('hidden');
  el.choicePanel.innerHTML = `<h3>무기 선택</h3><p>초보자 방망이를 내려놓고 주무기를 선택한다.</p>`;
  weapons.forEach(weapon => {
    const btn = document.createElement('button');
    btn.innerHTML = `${weapon.name}<small>${weapon.desc}</small>`;
    btn.onclick = () => {
      state.weapon = weapon;
      state.weaponChosen = true;
      state.locked = false;
      hideChoice();
      log(`${weapon.name}을 선택했다.`, 'important');
      if (shouldShowShop()) showShop(); else spawnEnemy();
      render();
    };
    el.choicePanel.appendChild(btn);
  });
}

function showShop() {
  state.locked = true;
  el.choicePanel.classList.remove('hidden');
  el.choicePanel.innerHTML = `<h3>상점</h3><p>보유 골드: ${state.gold}G</p>`;
  const items = [
    { name: '포션 구매', cost: 25, action: () => { state.potions += 1; log('포션을 1개 샀다.', 'good'); } },
    { name: '무기 강화', cost: 60, action: () => { state.weapon.attack += 3; log(`${state.weapon.name} 공격력이 3 올랐다.`, 'good'); } },
    { name: '방어 훈련', cost: 50, action: () => { state.maxHp += 15; state.hp += 15; log('최대 HP가 15 올랐다.', 'good'); } }
  ];

  items.forEach(item => {
    const btn = document.createElement('button');
    btn.innerHTML = `${item.name}<small>${item.cost}G</small>`;
    btn.disabled = state.gold < item.cost;
    btn.onclick = () => {
      if (state.gold < item.cost) return;
      state.gold -= item.cost;
      item.action();
      showShop();
      render();
    };
    el.choicePanel.appendChild(btn);
  });

  const next = document.createElement('button');
  next.innerHTML = `탑 오르기<small>다음 전투로 이동</small>`;
  next.onclick = () => {
    state.locked = false;
    hideChoice();
    spawnEnemy();
    render();
  };
  el.choicePanel.appendChild(next);
}

function hideChoice() {
  el.choicePanel.classList.add('hidden');
  el.choicePanel.innerHTML = '';
}

function ending() {
  state.gameOver = true;
  el.actions.querySelectorAll('button').forEach(btn => btn.disabled = true);
  log('엔더 드래곤이 무너지고 탑의 핵이 드러났다.', 'important');
  log('핵을 파괴했다. 검은 별빛은 멈췄지만, 하늘 너머에서 거대한 눈 하나가 떠오른다.', 'important');
  log('엔딩: 첫 번째 탑은 무너졌다. 두 번째 문이 열린다.', 'important');
  render();
}

function render() {
  const region = regionForFloor(state.floor);
  el.regionBadge.textContent = `${region.min}~${region.max}층 · ${region.name}`;
  el.scene.className = `scene ${region.key}`;
  const artPath = getEnemyArt(state.enemy?.name);
  el.monsterCard.classList.toggle('has-art', Boolean(artPath));
  el.monsterCard.style.setProperty('--monster-art', artPath ? `url("${artPath}")` : 'none');
  el.enemyType.textContent = state.enemy?.type ?? '-';
  el.enemyName.textContent = state.enemy?.name ?? '-';
  el.enemyHpText.textContent = `${state.enemy?.hp ?? 0} / ${state.enemy?.maxHp ?? 0}`;
  el.enemyHpBar.style.width = pct(state.enemy?.hp ?? 0, state.enemy?.maxHp ?? 1);
  el.storyTitle.textContent = region.name;
  el.storyText.textContent = region.story;

  el.floorText.textContent = `${state.floor}F`;
  el.weaponText.textContent = `무기: ${state.weapon.name} · 포션 ${state.potions}개`;
  el.playerHpText.textContent = `${state.hp} / ${state.maxHp}`;
  el.playerHpBar.style.width = pct(state.hp, state.maxHp);
  el.attackText.textContent = state.baseAttack + state.weapon.attack;
  el.speedText.textContent = state.weapon.speed;
  el.blockText.textContent = `${state.weapon.block}%`;
  el.goldText.textContent = state.gold;
  el.progressText.textContent = state.gameOver ? '모험 종료' : `목표: 100층 핵 파괴 · ${100 - state.floor}층 남음`;
  el.skillButton.textContent = state.weapon.skill;

  const disabled = state.locked || state.gameOver;
  el.attackButton.disabled = disabled;
  el.skillButton.disabled = disabled;
  el.potionButton.disabled = disabled;
}

function log(text, type = '') {
  const p = document.createElement('p');
  if (type) p.className = type;
  p.textContent = text;
  el.log.prepend(p);
}

function getEnemyArt(name) {
  const art = enemyArt[name];
  if (Array.isArray(art)) return art[state.floor % art.length];
  return art;
}

function pct(value, max) {
  return `${Math.max(0, Math.min(100, (value / max) * 100))}%`;
}

function randomInt(min, max) {
  return Math.floor(Math.random() * (max - min + 1)) + min;
}

el.attackButton.onclick = attack;
el.skillButton.onclick = skill;
el.potionButton.onclick = usePotion;
el.resetButton.onclick = () => {
  el.actions.querySelectorAll('button').forEach(btn => btn.disabled = false);
  hideChoice();
  newGame();
};

newGame();
