# TO DO List

## GENERAL APPROACH
HomeScreen shows a start session button, a calendar, and a list of historical sessions

## FEATURES TO BUILD
 ### DATA:
 - 

### INTERACTION:
- edit preset sessions
- onboarding screens
### UI:
- add supersets functionality

## BUGS:
- create tests for offline mode
- conflict resolution between local and cloud data
- in session_select_screen.dart, when no sessions exist, loading indicator shows forever?
- remove print statements
- force max number of workouts per session for UI constraints

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



## LATER STAGE
- timers without adding sessions/exercises first
- split add_item_screen into add_session_screen and add_workout_screen (code duplication, but also easier code)
- convert addExerciseModalSheet to a screen

### LATER IDEAS
- user profiles can search and add friends
- user can create public and private sessions
- user can add sessions from others (great for teams and coaches)



