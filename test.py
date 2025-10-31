from openai import OpenAI

client = OpenAI(api_key="")

response = client.responses.create(
    model="gpt-4o-mini",
    input='{"request_type":"student_question","question":"tell me a joke","code":"","progress":0.0}',
    instructions='''# OUTPUT FORMAT 
    Return valid JSON only. 
    { "type": "answer", 
    "answer": "short, clear, on-topic or empathetic response" 
}'''
)
print(response.output_text)

second_response = client.responses.create(
    model="gpt-4o-mini",
    previous_response_id=response.id,
    input='{"request_type":"student_question","question":"explain why this is funny","code":"","progress":0.0}',
    instructions='''# OUTPUT FORMAT 
    Return valid JSON only. 
    { "type": "answer", 
    "answer": "short, clear, on-topic or empathetic response" 
}'''
)

print(second_response.output_text)