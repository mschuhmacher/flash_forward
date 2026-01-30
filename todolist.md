# TO DO List
fl
## FEATURES TO BUILD
 ### DATA:
 - ask claude to put const wherever applicable for runtime optimization
 - ask claude to evaluate whether certain UI functions and/or widgets should be moved to separate widget files for readability of the files.

### INTERACTION:
- edit preset sessions
- onboarding screens
- edit button --> edit load for exercise
### UI:
- add supersets functionality
- background color of container/pop-up/dialog

## BUGS:
- create tests for offline mode
- conflict resolution between local and cloud data
- lower Sentry sample rates to traces: 0.2 and profiles: 0.1
- logged in to different user, session logs are now doubled?
  - also, user name did not display in app

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



## LATER STAGE
- timers without adding sessions/exercises first
- split add_item_screen into add_session_screen and add_workout_screen (code duplication, but also easier code)
- convert addExerciseModalSheet to a screen
- add Apple / Google auth

### LATER IDEAS
- user profiles can search and add friends
- user can create public and private sessions
- user can add sessions from others (great for teams and coaches)



