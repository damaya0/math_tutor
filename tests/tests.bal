import ballerina/ai;

isolated function loadEvalsetData() returns map<[ai:ConversationThread]>|error {
    return ai:loadConversationThreads("tests/resources/evalsets/math-tutor.evalset.json");
}

