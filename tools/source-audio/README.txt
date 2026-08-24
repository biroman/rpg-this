Raw recordings the game's audio is cut from.

Nothing in here ships. The .gdignore beside this file tells Godot to skip the
directory entirely, so these stay out of the import cache and out of builds.

tools/extract_audio.py cuts these into assets/audio/.

rpg-shot.mp3    three takes of an RPG shot: launch crack, a gap while the
                sustainer catches, then the motor running until it is out of
                earshot. The middle take becomes rocket_launch.wav and
                rocket_motor.wav.

explosion.mp3   one detonation, which becomes explosion.wav.
