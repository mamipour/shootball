# Disc Arena

**Penny Football — Reimagined**

A cross-platform multiplayer game built with Godot 4.x where players flick disc-shaped pills across various game fields using slingshot aiming. Play solo against AI or online against real opponents with server-authoritative physics.

## Game Modes

### CoinBall
Flick your pills through a central gate to score points. First to 3 wins.

### Football
Two goals, one ball. Flick your pills to push the ball into the opponent's goal. Multiple pills shoot simultaneously each round.

### Battle Arena
An arena with gravitational pits. Knock your opponent's pills into pits to eliminate them. Last team standing wins.

### Volleyball
A net divides the field. Smack the ball over to the opponent's side. Score when the ball lands on their half.

### Curling
Take turns sliding pills toward a target (the house). Closest pill to the button scores. First to 5 wins.

All five modes are available in both **solo** (vs AI) and **online** (vs real players) play.

## How to Play

1. **Aim** — Touch/click and drag behind your pill to set direction and power (slingshot style)
2. **Release** — Let go to shoot. In simultaneous modes, both players shoot blind at the same time.
3. **Watch** — Physics resolves collisions, bounces, and scoring automatically.
4. **Repeat** — Next round begins after all pills settle.

## Tech Stack

| Component | Technology |
|---|---|
| Game engine | Godot 4.6 (GDScript) |
| Multiplayer backend | [Nakama](https://heroiclabs.com/nakama/) |
| Server physics | Custom 2D circle physics engine (TypeScript) |
| Networking model | Server-authoritative with client-side trajectory replay |
| Target platforms | iOS, Android, Desktop |

## Project Structure

```
shootball/
├── addons/
│   └── com.heroiclabs.nakama/    # Nakama Godot SDK
├── assets/
│   ├── avatars/                  # 30 player avatar images
│   ├── sounds/                   # menu, goal, win, stadium audio
│   ├── Soccer_ball.svg           # Football ball sprite
│   ├── volleyball.svg            # Volleyball ball sprite
│   ├── goal_left.svg             # Goal sprites
│   ├── goal_right.svg
│   └── ...                       # Field textures, UI backgrounds
├── scenes/
│   ├── main_menu.tscn            # Entry point
│   ├── avatar_select.tscn        # Avatar picker
│   ├── online_lobby.tscn         # Online matchmaking lobby
│   ├── game.tscn                 # Solo CoinBall
│   ├── game_football.tscn        # Solo Football
│   ├── game_battle.tscn          # Solo Battle Arena
│   ├── game_volleyball.tscn      # Solo Volleyball
│   ├── game_curling.tscn         # Solo Curling
│   ├── game_online.tscn          # Online CoinBall
│   ├── game_online_football.tscn # Online Football
│   ├── game_online_battle.tscn   # Online Battle Arena
│   ├── game_online_volleyball.tscn # Online Volleyball
│   └── game_online_curling.tscn  # Online Curling
├── scripts/
│   ├── constants.gd              # Shared game constants (autoload)
│   ├── online.gd                 # Nakama client wrapper (autoload)
│   ├── main_menu.gd              # Main menu logic
│   ├── online_lobby.gd           # Matchmaking lobby
│   ├── avatar_select.gd          # Avatar selection
│   ├── pill.gd                   # RigidBody2D pill (player piece)
│   ├── ai_player.gd              # AI opponent logic
│   ├── game.gd                   # Solo CoinBall
│   ├── game_football.gd          # Solo Football
│   ├── game_battle.gd            # Solo Battle Arena
│   ├── game_volleyball.gd        # Solo Volleyball
│   ├── game_curling.gd           # Solo Curling
│   ├── game_online.gd            # Online CoinBall
│   ├── game_online_football.gd   # Online Football
│   ├── game_online_battle.gd     # Online Battle Arena
│   ├── game_online_volleyball.gd # Online Volleyball
│   └── game_online_curling.gd    # Online Curling
└── project.godot
```

The server-side code lives in a sibling directory (`shootball-server/`) and runs on Nakama with a custom TypeScript match handler that performs all physics simulation and game state management.

## Architecture

### Solo Play
The client runs Godot's built-in physics engine locally. An AI opponent (with Easy/Normal/Hard difficulty) selects shots using raycast-based strategy evaluation.

### Online Play
1. Both players submit their shot inputs to the server.
2. The server runs a custom 2D physics simulation (circle-circle and circle-wall collisions).
3. The server sends back an `OP_SIM_RESULT` containing the full trajectory of all objects, frame by frame, plus game outcome data (goals, eliminations, scores).
4. Clients replay the trajectory by directly positioning frozen physics bodies, ensuring both players see identical results.
5. After replay completes, clients send a ready signal and the next round begins.

This server-authoritative model eliminates desync issues that arise from floating-point differences between clients.

## Configuration

| Setting | Location | Default |
|---|---|---|
| Viewport size | `project.godot` | 1280 x 720 |
| AI difficulty | `user://settings.cfg` | Normal (1) |
| Master volume | `user://settings.cfg` | 0.5 |
| Player avatar | `user://settings.cfg` | 0 |
| Server host | `scripts/online.gd` | `shootball.avardgah.com:7350` |

## Running Locally

### Client
1. Open the project in **Godot 4.6+**
2. Run the main scene (`scenes/main_menu.tscn`)

### Server
1. Navigate to `../shootball-server/`
2. Run `npx tsc` to compile TypeScript
3. Start the Nakama server via Docker Compose:
   ```
   docker compose up -d
   ```

## License

All rights reserved.
