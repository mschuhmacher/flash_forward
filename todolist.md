# TO DO List

## FEATURES TO BUILD

### PROCES:
- Apple Store Connect:
  - add business name?

### DATA:


### INTERACTION:
- edit preset sessions
- unshow preset sessions
- onboarding screens
- edit button --> edit load for exercise
- active screen: buttons for next/prev set/rep?
### UI:
- add supersets functionality
- remove individual logged sessions by swiping them


## BUGS:
- create tests for offline mode
- conflict resolution between local and cloud data


## IDEAS:
- user can start only a workout or exercise
  - toggle for starting a session or only a workout or exercise
- overhaul session select workflow
  - bottom navigation bar with:
    - homescreen for logged workouts
    - edit sessions / workouts / exercises screen
    - profile page 
        - app theme toggle
        - clear logs
        - privacy statement
    - Grid view of different labels / phases of exercises
        - Warm-up, Climbing, Gym, Stretching, Skills, Daily?
        - Click on grid item to go to all workouts of that type
        - Can only add new workouts within this screen
        - scrollable list with horizontal scroll per section (label)??
- long press the pause button during an exercise to keep the timer running and going over the normal time. Loop icon
- lbs vs kg setting
- support band resistance in exercises
- add animations
  - between timerphase text
  - between exercises / workouts
  - between workoutNames list
- edit load and reps for each set
- add logger package for loca debugging during dev
- ask claude to put const wherever applicable for runtime optimization
- ask claude to evaluate whether certain UI functions and/or widgets should be moved to separate widget files for readability of the files.
- ask claude for looking up flutter framework on code design and evaluate my codebase
- health check to my Supabase URL using a cron-job to keep the project from pausing
- option for exercises to have no time. in practice: timer keeps running until user clicks to next exercise


## LATER STAGE
- timers without adding sessions/exercises first
- split add_item_screen into add_session_screen and add_workout_screen (code duplication, but also easier code)
- convert addExerciseModalSheet to a screen
- add Apple / Google auth

### LATER IDEAS
- user profiles can search and add friends
- user can create public and private sessions
- user can add sessions from others (great for teams and coaches)



