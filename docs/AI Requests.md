

# Hint
The first one is a hint. When the student is stuck on an exercise, the can click the 'hint' button. This will send a request for a hint. Below is what we expect to send and recieve.

Request:

``` JSON
{
    request_type: "hint",
    exercise: "The instructions the student got",
    code: "the current code this student has",
    goal: {
        name: "the name of the goal",
        advancement: "number between 0 and 1 indicates how the student progresses on this goal",
        current_subgoal: {
            name: "the name of the subgoal",
            advancement: "number between 0 and 1 indicates how the student progresses on this goal",
            suggestions: [
                "the list of suggestions for this subgoal",
            ],
        },
    },
    knowlegde: "We should provide what the student already knows, because otherwise the AI might hint at something the student does not know yet",
    previous_hints: "list of previous hints. We don't want to repeat ourselves. And if there is no progress, we can look at this and see how to add more detail",
    answer_format: {
        response_type: "hint",
        response: "the actual hint",
    }
}
```

Response:

```JSON
{
    response_type: "hint",
    response: "the actual hint",
}
```

# CodeSubmit
When the user got an exercise to complete and submits their code, AI is expected to evaluate the code. At this point, the AI needs to make decisions:

- there are errors:
    - this is the first error, or a previous error was fixed but now there is another one:
        - reply with a hint
    - we gave several hints and there is no progress:
        - we explain in detail what is wrong in detail and ask them to fix the code and submit it again.

- the answer is correct:
    - it can be improved upon:
        - give a hint that makes the user come up with a better answer
    - it can be improved upon, but the hint did not help:
        - explain in detail, but confirm their answer is not wrong.
        - update advancement for this subgoal
    - the answer is good:
        - update update advancement for this subgoal

This means the JSON request must provide enough information to make these decisions

Request:

``` JSON
{
    request_type: "code_submit",
    exercise: "The instructions the student got",
    code: "the current code this student has",
    goal: {
        name: "the name of the goal",
        advancement: "number between 0 and 1 indicates how the student progresses on this goal",
        current_subgoal: {
            name: "the name of the subgoal",
            advancement: "number between 0 and 1 indicates how the student progresses on this goal",
            suggestions: [
                "the list of suggestions for this subgoal",
            ],
        },
    },
    knowlegde: "We should provide what the student already knows, because otherwise the AI might hint at something the student does not know yet",
    answer_format: {
        errors
        response_type: "hint",
        response: "the actual hint",
    }
}
```

```JSON
{
    "request_type": "generate exercise",
    "progress": 0.75
}
{
    "request_type": "mpc_answer",
    "choice": "A"
}
{
    "request_type": "submit_code",
    "code": "print('I have', 3 , 'apples')"
}
```