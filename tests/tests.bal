import ballerina/ai;
import ballerina/test;

isolated function loadEvalsetData1() returns map<[ai:ConversationThread]>|error {
    return check ai:loadConversationThreads("evalsets/math-tutor.evalset.json");
}

@test:Config {
    groups: ["evaluations"],
    minPassRate: 0.8,
    dataProvider: loadEvalsetData1
}
function evaluateResponseClarity(ai:ConversationThread thread) returns error? {
    float totalAchievedScore = 0.0;
    float maxPossibleScore = thread.traces.count() * 5.0;
    float THRESHOLD = 0.8;

    foreach ai:Trace trace in thread.traces {
        ai:Trace actualTrace = check mathTutorAgent.run(trace.userMessage.content.toString(), thread.id);

        string expectedOutput = (check trace.output).content.toString();
        string actualOutput = (check actualTrace.output).content.toString();

        // LLM as a Judge evaluates the response
        float judgeResult = check judgeModel->generate(`You are a strict, expert evaluator grading a Math Tutor agent. Compare the ACTUAL OUTPUT to the EXPECTED OUTPUT.

Your primary focus is ensuring the agent provides **clear, step-by-step explanations**. Correct math alone is NOT enough.

Rate the output on a scale of 1 to 5 based on this strict rubric: 

* 1 = Incorrect math, OR the math is correct but there is ZERO step-by-step explanation. 

* 2 = Correct math, but the explanation skips major logical steps or just blurts out the answer. 

* 3 = Correct math, but the explanation is vague, confusing, or lacks the depth of the Expected Output. 

* 4 = Correct math and a good step-by-step explanation, but missing minor details compared to the Expected Output. 

* 5 = Perfect mathematical accuracy AND a crystal-clear, exhaustive, step-by-step explanation that perfectly matches or exceeds the Expected Output.

Expected Output: ${expectedOutput}

Actual Output: ${actualOutput}

Output ONLY the integer number (1, 2, 3, 4, or 5). Do not include any other text, whitespace, or reasoning.`);

        totalAchievedScore = totalAchievedScore + judgeResult;
    }

    float finalThreadScore = totalAchievedScore / maxPossibleScore;

    test:assertTrue(
            finalThreadScore >= THRESHOLD,
            msg = string `Thread failed. Cumulative score ${finalThreadScore} is below threshold ${THRESHOLD}.`
    );
}

final ai:Wso2ModelProvider judgeModel = check ai:getDefaultModelProvider();

isolated function loadEvalsetData() returns map<[ai:ConversationThread]>|error {
    return ai:loadConversationThreads("evalsets/math-tutor.evalset.json");
}

@test:Config {
    groups: ["evaluations"],
    minPassRate: 0.8,
    dataProvider: loadEvalsetData
}
function evaluateToolTrajectory(ai:ConversationThread thread) returns error? {
    foreach ai:Trace trace in thread.traces {
        ai:Trace traceResult = check mathTutorAgent.run(trace.userMessage.content.toString(), thread.id);
        test:assertEquals(traceResult.toolCalls, trace.toolCalls);
    }
}
