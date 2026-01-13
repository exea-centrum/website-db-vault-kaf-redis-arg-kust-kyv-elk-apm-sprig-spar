#!/bin/bash
set -euo pipefail

# Katalogi
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFESTS_DIR="${PROJECT_DIR}/manifests/base"
APP_DIR="${PROJECT_DIR}/app"
JAVA_DIR="${PROJECT_DIR}/java-app"
SPARK_DIR="${PROJECT_DIR}/spark-jobs"
ELK_DIR="${PROJECT_DIR}/elk"

# Funkcje pomocnicze
info() { echo "🔧 $*"; }
mkdir_p() { mkdir -p "$@"; }

# ========== 1. DODANIE NOWEJ ANKIETY JAVASCRIPT ==========

mkdir_p "${APP_DIR}/static/js" "${APP_DIR}/static/css"

cat > "${APP_DIR}/static/js/new-survey.js" <<'JS'
// Nowa ankieta JavaScript z React-like komponentami
class NewSurveyApp {
    constructor() {
        this.state = {
            questions: [],
            answers: {},
            submitted: false,
            stats: null
        };
        this.init();
    }

    async init() {
        await this.loadQuestions();
        this.render();
        this.setupEventListeners();
    }

    async loadQuestions() {
        try {
            const response = await fetch('/api/v2/survey/questions');
            this.state.questions = await response.json();
            this.render();
        } catch (error) {
            console.error('Error loading questions:', error);
        }
    }

    async loadStats() {
        try {
            const response = await fetch('/api/v2/survey/stats');
            this.state.stats = await response.json();
            this.renderStats();
        } catch (error) {
            console.error('Error loading stats:', error);
        }
    }

    handleAnswer(questionId, value) {
        this.state.answers[questionId] = value;
        this.render();
    }

    async submitSurvey() {
        const responses = Object.entries(this.state.answers).map(([qId, answer]) => ({
            questionId: qId,
            question: this.state.questions.find(q => q.id == qId)?.text || '',
            answer: answer,
            timestamp: new Date().toISOString(),
            surveyType: 'java-survey'
        }));

        try {
            const response = await fetch('/api/v2/survey/submit', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ responses })
            });
            
            if (response.ok) {
                this.state.submitted = true;
                this.state.answers = {};
                await this.loadStats();
                this.showMessage('Ankieta została przesłana! Dziękujemy.', 'success');
            }
        } catch (error) {
            this.showMessage('Błąd podczas wysyłania ankiety', 'error');
        }
    }

    showMessage(text, type) {
        const messageDiv = document.getElementById('survey-message');
        messageDiv.textContent = text;
        messageDiv.className = `message ${type}`;
        messageDiv.style.display = 'block';
        setTimeout(() => messageDiv.style.display = 'none', 5000);
    }

    render() {
        const container = document.getElementById('new-survey-container');
        if (!container) return;

        container.innerHTML = `
            <div class="survey-header">
                <h2>🚀 Nowa Ankieta Technologiczna (JavaScript + Spring Boot)</h2>
                <p>Oceń nasze nowe technologie: Spring Boot, Apache Spark, MongoDB, ELK Stack</p>
            </div>
            
            ${this.state.questions.map(q => `
                <div class="question-card">
                    <h3>${q.text}</h3>
                    <div class="options">
                        ${this.renderQuestionInput(q)}
                    </div>
                </div>
            `).join('')}
            
            <button id="submit-survey-btn" class="submit-btn">
                ${this.state.submitted ? '✓ Wysłano!' : 'Wyślij ankietę'}
            </button>
            
            <div id="survey-message" class="message"></div>
        `;
    }

    renderQuestionInput(question) {
        switch(question.type) {
            case 'rating':
                return `
                    <div class="rating-buttons">
                        ${[1,2,3,4,5].map(num => `
                            <button class="rating-btn ${this.state.answers[question.id] == num ? 'selected' : ''}"
                                    onclick="surveyApp.handleAnswer(${question.id}, ${num})">
                                ${num}
                            </button>
                        `).join('')}
                    </div>
                `;
            case 'choice':
                return `
                    <div class="choice-buttons">
                        ${question.options.map(opt => `
                            <button class="choice-btn ${this.state.answers[question.id] == opt ? 'selected' : ''}"
                                    onclick="surveyApp.handleAnswer(${question.id}, '${opt}')">
                                ${opt}
                            </button>
                        `).join('')}
                    </div>
                `;
            case 'text':
                return `
                    <textarea class="text-answer" 
                              placeholder="${question.placeholder}"
                              oninput="surveyApp.handleAnswer(${question.id}, this.value)">
                    </textarea>
                `;
            default:
                return '';
        }
    }

    renderStats() {
        const statsContainer = document.getElementById('survey-stats-container');
        if (!statsContainer || !this.state.stats) return;

        statsContainer.innerHTML = `
            <h3>📊 Statystyki ankiety (Spring Boot + MongoDB)</h3>
            <div class="stats-grid">
                <div class="stat-card">
                    <div class="stat-value">${this.state.stats.totalResponses}</div>
                    <div class="stat-label">Wszystkich odpowiedzi</div>
                </div>
                <div class="stat-card">
                    <div class="stat-value">${this.state.stats.avgRating?.toFixed(1) || '0.0'}</div>
                    <div class="stat-label">Średnia ocena</div>
                </div>
                <div class="stat-card">
                    <div class="stat-value">${this.state.stats.uniqueUsers}</div>
                    <div class="stat-label">Unikalnych użytkowników</div>
                </div>
            </div>
            
            <div class="charts">
                <canvas id="rating-chart" width="400" height="200"></canvas>
                <canvas id="tech-chart" width="400" height="200"></canvas>
            </div>
        `;

        this.renderCharts();
    }

    renderCharts() {
        // Implementacja wykresów Chart.js
        if (window.Chart && this.state.stats?.charts) {
            new Chart(document.getElementById('rating-chart'), {
                type: 'bar',
                data: this.state.stats.charts.ratings
            });
            
            new Chart(document.getElementById('tech-chart'), {
                type: 'pie',
                data: this.state.stats.charts.technologies
            });
        }
    }

    setupEventListeners() {
        document.addEventListener('click', (e) => {
            if (e.target.id === 'submit-survey-btn') {
                this.submitSurvey();
            }
        });
    }
}

// Globalna instancja
window.surveyApp = new NewSurveyApp();
JS

cat > "${APP_DIR}/static/css/new-survey.css" <<'CSS'
/* Stylizacja nowej ankiety */
.new-survey-section {
    background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
    border-radius: 20px;
    padding: 2rem;
    margin: 2rem 0;
    color: white;
}

.survey-header {
    text-align: center;
    margin-bottom: 2rem;
}

.survey-header h2 {
    font-size: 2rem;
    margin-bottom: 0.5rem;
}

.survey-header p {
    opacity: 0.9;
    font-size: 1.1rem;
}

.question-card {
    background: rgba(255, 255, 255, 0.1);
    backdrop-filter: blur(10px);
    border-radius: 15px;
    padding: 1.5rem;
    margin: 1rem 0;
    border: 1px solid rgba(255, 255, 255, 0.2);
}

.question-card h3 {
    margin-bottom: 1rem;
    font-size: 1.3rem;
}

.rating-buttons {
    display: flex;
    gap: 0.5rem;
    justify-content: center;
}

.rating-btn {
    width: 50px;
    height: 50px;
    border-radius: 50%;
    border: 2px solid rgba(255, 255, 255, 0.3);
    background: rgba(255, 255, 255, 0.1);
    color: white;
    font-size: 1.2rem;
    cursor: pointer;
    transition: all 0.3s ease;
}

.rating-btn:hover {
    background: rgba(255, 255, 255, 0.2);
    transform: translateY(-2px);
}

.rating-btn.selected {
    background: #4ade80;
    border-color: #22c55e;
    transform: scale(1.1);
}

.choice-buttons {
    display: flex;
    flex-wrap: wrap;
    gap: 0.5rem;
}

.choice-btn {
    padding: 0.75rem 1.5rem;
    border-radius: 50px;
    border: 2px solid rgba(255, 255, 255, 0.3);
    background: rgba(255, 255, 255, 0.1);
    color: white;
    cursor: pointer;
    transition: all 0.3s ease;
}

.choice-btn:hover {
    background: rgba(255, 255, 255, 0.2);
}

.choice-btn.selected {
    background: #3b82f6;
    border-color: #1d4ed8;
}

.text-answer {
    width: 100%;
    min-height: 100px;
    padding: 1rem;
    border-radius: 10px;
    border: 2px solid rgba(255, 255, 255, 0.3);
    background: rgba(255, 255, 255, 0.1);
    color: white;
    resize: vertical;
}

.text-answer::placeholder {
    color: rgba(255, 255, 255, 0.6);
}

.submit-btn {
    display: block;
    width: 100%;
    padding: 1rem;
    margin-top: 2rem;
    background: linear-gradient(135deg, #4ade80 0%, #22c55e 100%);
    color: white;
    border: none;
    border-radius: 10px;
    font-size: 1.2rem;
    font-weight: bold;
    cursor: pointer;
    transition: all 0.3s ease;
}

.submit-btn:hover {
    transform: translateY(-2px);
    box-shadow: 0 10px 20px rgba(34, 197, 94, 0.3);
}

.message {
    margin-top: 1rem;
    padding: 1rem;
    border-radius: 10px;
    text-align: center;
    font-weight: bold;
}

.message.success {
    background: rgba(34, 197, 94, 0.2);
    border: 2px solid #22c55e;
    color: #22c55e;
}

.message.error {
    background: rgba(239, 68, 68, 0.2);
    border: 2px solid #ef4444;
    color: #ef4444;
}

.stats-grid {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
    gap: 1rem;
    margin: 2rem 0;
}

.stat-card {
    background: rgba(255, 255, 255, 0.1);
    border-radius: 15px;
    padding: 1.5rem;
    text-align: center;
    backdrop-filter: blur(10px);
}

.stat-value {
    font-size: 2.5rem;
    font-weight: bold;
    margin-bottom: 0.5rem;
}

.stat-label {
    opacity: 0.8;
    font-size: 0.9rem;
}

.charts {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 2rem;
    margin-top: 2rem;
}

@media (max-width: 768px) {
    .charts {
        grid-template-columns: 1fr;
    }
}
CSS

# ========== 2. DODANIE ENDPOINTÓW SPRING BOOT W FASTAPI (proxy) ==========

cat > "${APP_DIR}/spring_proxy.py" <<'PY'
"""
Proxy do komunikacji z Spring Boot API
"""
from fastapi import APIRouter, HTTPException
import httpx
import logging
from typing import List, Dict, Any

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/api/v2", tags=["spring-survey"])

# Konfiguracja Spring Boot API
SPRING_API_URL = "http://spring-app-service:8080/api"

@router.get("/survey/questions")
async def get_spring_survey_questions():
    """
    Pobiera pytania z Spring Boot API
    """
    try:
        async with httpx.AsyncClient() as client:
            response = await client.get(
                f"{SPRING_API_URL}/survey/questions",
                timeout=10.0
            )
            response.raise_for_status()
            return response.json()
    except Exception as e:
        logger.error(f"Error fetching questions from Spring: {e}")
        # Fallback questions
        return [
            {
                "id": 1,
                "text": "Jak oceniasz wydajność Spring Boot API?",
                "type": "rating",
                "options": ["1 - Słabo", "2", "3", "4", "5 - Doskonale"]
            },
            {
                "id": 2,
                "text": "Która technologia Java Cię interesuje?",
                "type": "choice",
                "options": ["Spring Boot", "Apache Spark", "Hibernate", "MongoDB", "Kafka Streams"]
            },
            {
                "id": 3,
                "text": "Jak oceniasz integrację z Python/FastAPI?",
                "type": "rating",
                "options": ["1 - Słaba", "2", "3", "4", "5 - Doskonała"]
            },
            {
                "id": 4,
                "text": "Czy uważasz, że ELK Stack jest przydatny?",
                "type": "choice",
                "options": ["Tak, zdecydowanie", "Raczej tak", "Nie wiem", "Raczej nie", "Nie"]
            },
            {
                "id": 5,
                "text": "Twoje sugestie dotyczące architektury:",
                "type": "text",
                "placeholder": "Podziel się swoimi pomysłami..."
            }
        ]

@router.post("/survey/submit")
async def submit_spring_survey(data: Dict[str, Any]):
    """
    Wysyła odpowiedzi do Spring Boot API
    """
    try:
        async with httpx.AsyncClient() as client:
            response = await client.post(
                f"{SPRING_API_URL}/survey/submit",
                json=data,
                timeout=10.0
            )
            response.raise_for_status()
            return response.json()
    except Exception as e:
        logger.error(f"Error submitting to Spring: {e}")
        raise HTTPException(
            status_code=500,
            detail=f"Error submitting survey: {str(e)}"
        )

@router.get("/survey/stats")
async def get_spring_survey_stats():
    """
    Pobiera statystyki z Spring Boot API
    """
    try:
        async with httpx.AsyncClient() as client:
            response = await client.get(
                f"{SPRING_API_URL}/survey/stats",
                timeout=10.0
            )
            response.raise_for_status()
            return response.json()
    except Exception as e:
        logger.error(f"Error fetching stats from Spring: {e}")
        return {
            "totalResponses": 0,
            "avgRating": 0.0,
            "uniqueUsers": 0,
            "charts": {
                "ratings": {"labels": [], "datasets": []},
                "technologies": {"labels": [], "datasets": []}
            }
        }

@router.get("/spark/jobs")
async def get_spark_jobs():
    """
    Pobiera status zadań Spark
    """
    try:
        async with httpx.AsyncClient() as client:
            response = await client.get(
                "http://spark-master:8080/api/v1/applications",
                timeout=10.0
            )
            response.raise_for_status()
            return response.json()
    except Exception as e:
        logger.error(f"Error fetching Spark jobs: {e}")
        return []

@router.get("/elk/logs")
async def search_elk_logs(query: str = "", size: int = 10):
    """
    Wyszukuje logi w Elasticsearch
    """
    try:
        async with httpx.AsyncClient() as client:
            es_query = {
                "query": {
                    "bool": {
                        "must": [
                            {"match": {"message": query}} if query else {"match_all": {}}
                        ]
                    }
                },
                "size": size,
                "sort": [{"@timestamp": {"order": "desc"}}]
            }
            
            response = await client.post(
                "http://elasticsearch:9200/logs*/_search",
                json=es_query,
                headers={"Content-Type": "application/json"},
                timeout=10.0
            )
            response.raise_for_status()
            return response.json()
    except Exception as e:
        logger.error(f"Error searching ELK logs: {e}")
        return {"hits": {"hits": []}}
PY

# ========== 3. DODANIE HTML DLA NOWEJ ANKIETY ==========

cat > "${APP_DIR}/templates/new_survey.html" <<'HTML'
<!DOCTYPE html>
<html lang="pl">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Nowa Ankieta - Spring Boot + JavaScript</title>
    <script src="https://cdn.tailwindcss.com"></script>
    <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
    <link rel="stylesheet" href="/static/css/new-survey.css">
    <style>
        body {
            background: linear-gradient(135deg, #0f172a 0%, #1e293b 100%);
            min-height: 100vh;
            color: #e2e8f0;
        }
        
        .tech-badge {
            display: inline-block;
            padding: 0.25rem 0.75rem;
            margin: 0.25rem;
            background: rgba(59, 130, 246, 0.2);
            border: 1px solid rgba(59, 130, 246, 0.5);
            border-radius: 20px;
            font-size: 0.875rem;
            color: #93c5fd;
        }
        
        .architecture-diagram {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
            gap: 1rem;
            margin: 2rem 0;
        }
        
        .arch-node {
            background: rgba(255, 255, 255, 0.05);
            border: 1px solid rgba(255, 255, 255, 0.1);
            border-radius: 10px;
            padding: 1rem;
            text-align: center;
        }
        
        .arch-node.spring {
            border-color: #6db33f;
            background: rgba(109, 179, 63, 0.1);
        }
        
        .arch-node.spark {
            border-color: #e25a1c;
            background: rgba(226, 90, 28, 0.1);
        }
        
        .arch-node.mongodb {
            border-color: #47a248;
            background: rgba(71, 162, 72, 0.1);
        }
        
        .arch-node.elastic {
            border-color: #005571;
            background: rgba(0, 85, 113, 0.1);
        }
    </style>
</head>
<body>
    <div class="container mx-auto px-4 py-8">
        <!-- Nagłówek -->
        <div class="text-center mb-12">
            <h1 class="text-4xl font-bold mb-4 bg-gradient-to-r from-blue-400 to-purple-400 bg-clip-text text-transparent">
                🚀 Nowa Architektura: Spring Boot + JavaScript + Apache Spark
            </h1>
            <p class="text-xl text-gray-300 mb-6">
                Hybrydowa platforma łącząca Python, Java, JavaScript i Big Data
            </p>
            <div class="flex flex-wrap justify-center gap-2 mb-8">
                <span class="tech-badge">Spring Boot 3.1</span>
                <span class="tech-badge">Apache Spark 3.4</span>
                <span class="tech-badge">MongoDB 7.0</span>
                <span class="tech-badge">Elasticsearch 8.10</span>
                <span class="tech-badge">Kafka Streams</span>
                <span class="tech-badge">JavaScript ES2022</span>
            </div>
        </div>

        <!-- Diagram architektury -->
        <div class="mb-12">
            <h2 class="text-2xl font-bold mb-6 text-center">🏗️ Architektura Systemu</h2>
            <div class="architecture-diagram">
                <div class="arch-node spring">
                    <div class="text-3xl mb-2">🌱</div>
                    <h3 class="font-bold text-lg">Spring Boot API</h3>
                    <p class="text-sm text-gray-400">REST API w Javie z MongoDB</p>
                </div>
                
                <div class="arch-node spark">
                    <div class="text-3xl mb-2">⚡</div>
                    <h3 class="font-bold text-lg">Apache Spark</h3>
                    <p class="text-sm text-gray-400">Przetwarzanie danych w czasie rzeczywistym</p>
                </div>
                
                <div class="arch-node mongodb">
                    <div class="text-3xl mb-2">🍃</div>
                    <h3 class="font-bold text-lg">MongoDB</h3>
                    <p class="text-sm text-gray-400">NoSQL dla danych ankietowych</p>
                </div>
                
                <div class="arch-node elastic">
                    <div class="text-3xl mb-2">🔍</div>
                    <h3 class="font-bold text-lg">ELK Stack</h3>
                    <p class="text-sm text-gray-400">Logi, wyszukiwanie, wizualizacja</p>
                </div>
            </div>
        </div>

        <!-- Nowa ankieta -->
        <div class="new-survey-section">
            <div id="new-survey-container">
                <!-- Dynamicznie wypełniane przez JavaScript -->
            </div>
        </div>

        <!-- Statystyki -->
        <div class="mt-12">
            <div id="survey-stats-container">
                <!-- Dynamicznie wypełniane przez JavaScript -->
            </div>
        </div>

        <!-- Panel administracyjny -->
        <div class="mt-12 grid grid-cols-1 md:grid-cols-2 gap-6">
            <!-- Status Spark -->
            <div class="bg-gray-800 rounded-xl p-6">
                <h3 class="text-xl font-bold mb-4">⚡ Apache Spark Jobs</h3>
                <div id="spark-jobs" class="space-y-2">
                    <div class="animate-pulse">Ładowanie zadań Spark...</div>
                </div>
                <button onclick="loadSparkJobs()" class="mt-4 px-4 py-2 bg-orange-500 text-white rounded-lg hover:bg-orange-600">
                    Odśwież status
                </button>
            </div>

            <!-- Wyszukiwarka logów -->
            <div class="bg-gray-800 rounded-xl p-6">
                <h3 class="text-xl font-bold mb-4">🔍 Wyszukiwarka Logów (ELK)</h3>
                <div class="flex gap-2 mb-4">
                    <input type="text" id="log-search" placeholder="Szukaj w logach..." 
                           class="flex-1 px-4 py-2 bg-gray-700 text-white rounded-lg">
                    <button onclick="searchLogs()" class="px-4 py-2 bg-blue-500 text-white rounded-lg hover:bg-blue-600">
                        Szukaj
                    </button>
                </div>
                <div id="logs-results" class="space-y-2 max-h-60 overflow-y-auto">
                    <!-- Wyniki wyszukiwania -->
                </div>
            </div>
        </div>

        <!-- Instrukcja -->
        <div class="mt-12 bg-gradient-to-r from-purple-900/30 to-blue-900/30 rounded-xl p-6">
            <h3 class="text-xl font-bold mb-4">📚 Jak działa system?</h3>
            <ol class="list-decimal list-inside space-y-2">
                <li>Ankieta JavaScript wysyła dane do Spring Boot API</li>
                <li>Spring Boot zapisuje dane w MongoDB</li>
                <li>Apache Spark przetwarza dane w czasie rzeczywistym</li>
                <li>Logi trafiają do ELK Stack (Elasticsearch, Logstash, Kibana)</li>
                <li>Prometheus zbiera metryki, Grafana wizualizuje</li>
                <li>Wszystkie komponenty komunikują się przez Kafka</li>
            </ol>
        </div>
    </div>

    <!-- Skrypty -->
    <script src="/static/js/new-survey.js"></script>
    <script>
        // Funkcje pomocnicze
        async function loadSparkJobs() {
            try {
                const response = await fetch('/api/v2/spark/jobs');
                const jobs = await response.json();
                
                const container = document.getElementById('spark-jobs');
                if (jobs.length === 0) {
                    container.innerHTML = '<div class="text-gray-400">Brak aktywnych zadań Spark</div>';
                    return;
                }
                
                container.innerHTML = jobs.map(job => `
                    <div class="p-3 bg-gray-900 rounded-lg">
                        <div class="flex justify-between items-center">
                            <span class="font-medium">${job.name}</span>
                            <span class="px-2 py-1 text-xs rounded ${job.state === 'RUNNING' ? 'bg-green-500' : 'bg-yellow-500'}">
                                ${job.state}
                            </span>
                        </div>
                        <div class="text-sm text-gray-400 mt-1">ID: ${job.id}</div>
                    </div>
                `).join('');
            } catch (error) {
                console.error('Error loading Spark jobs:', error);
                document.getElementById('spark-jobs').innerHTML = 
                    '<div class="text-red-400">Błąd ładowania zadań Spark</div>';
            }
        }

        async function searchLogs() {
            const query = document.getElementById('log-search').value;
            
            try {
                const response = await fetch(`/api/v2/elk/logs?query=${encodeURIComponent(query)}`);
                const data = await response.json();
                
                const container = document.getElementById('logs-results');
                const hits = data.hits?.hits || [];
                
                if (hits.length === 0) {
                    container.innerHTML = '<div class="text-gray-400">Brak wyników</div>';
                    return;
                }
                
                container.innerHTML = hits.map(hit => {
                    const source = hit._source;
                    return `
                        <div class="p-3 bg-gray-900 rounded-lg">
                            <div class="text-sm font-medium">${source.message || 'Brak wiadomości'}</div>
                            <div class="text-xs text-gray-400 mt-1">
                                ${source['@timestamp'] || new Date().toISOString()}
                            </div>
                            ${source.level ? `<span class="text-xs px-2 py-1 rounded ${source.level === 'ERROR' ? 'bg-red-500' : 'bg-blue-500'}">${source.level}</span>` : ''}
                        </div>
                    `;
                }).join('');
            } catch (error) {
                console.error('Error searching logs:', error);
                document.getElementById('logs-results').innerHTML = 
                    '<div class="text-red-400">Błąd wyszukiwania logów</div>';
            }
        }

        // Inicjalizacja
        document.addEventListener('DOMContentLoaded', () => {
            loadSparkJobs();
            // Ładujemy statystyki co 30 sekund
            setInterval(() => surveyApp.loadStats(), 30000);
        });
    </script>
</body>
</html>
HTML

# ========== 4. DODANIE APLIKACJI SPRING BOOT ==========

mkdir_p "${JAVA_DIR}/src/main/java/com/davtroweb/survey"

# Main aplikacji Spring Boot
cat > "${JAVA_DIR}/src/main/java/com/davtroweb/survey/SurveyApplication.java" <<'JAVA'
package com.davtroweb.survey;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.data.mongodb.config.EnableMongoAuditing;
import org.springframework.scheduling.annotation.EnableScheduling;
import org.springframework.kafka.annotation.EnableKafka;

@SpringBootApplication
@EnableMongoAuditing
@EnableScheduling
@EnableKafka
public class SurveyApplication {
    public static void main(String[] args) {
        SpringApplication.run(SurveyApplication.class, args);
    }
}
JAVA

# Model MongoDB
cat > "${JAVA_DIR}/src/main/java/com/davtroweb/survey/model/SurveyResponse.java" <<'JAVA'
package com.davtroweb.survey.model;

import lombok.Data;
import lombok.NoArgsConstructor;
import lombok.AllArgsConstructor;
import org.springframework.data.annotation.Id;
import org.springframework.data.mongodb.core.mapping.Document;
import org.springframework.data.mongodb.core.index.Indexed;
import java.time.LocalDateTime;
import java.util.Map;

@Data
@NoArgsConstructor
@AllArgsConstructor
@Document(collection = "survey_responses")
public class SurveyResponse {
    
    @Id
    private String id;
    
    @Indexed
    private String surveyId;
    
    private String userId;
    private String sessionId;
    
    private Map<String, Object> answers;
    private SurveyMetadata metadata;
    
    @Indexed
    private LocalDateTime submittedAt;
    
    @Data
    @NoArgsConstructor
    @AllArgsConstructor
    public static class SurveyMetadata {
        private String surveyType;
        private String browser;
        private String ipAddress;
        private String userAgent;
        private String referer;
        private Map<String, Object> technicalData;
    }
}
JAVA

# Model dla analiz Spark
cat > "${JAVA_DIR}/src/main/java/com/davtroweb/survey/model/SparkAnalytics.java" <<'JAVA'
package com.davtroweb.survey.model;

import lombok.Data;
import lombok.NoArgsConstructor;
import lombok.AllArgsConstructor;
import org.springframework.data.annotation.Id;
import org.springframework.data.mongodb.core.mapping.Document;
import org.springframework.data.mongodb.core.index.CompoundIndex;
import java.time.LocalDateTime;
import java.util.Map;

@Data
@NoArgsConstructor
@AllArgsConstructor
@Document(collection = "spark_analytics")
@CompoundIndex(name = "type_timestamp_idx", def = "{'analysisType': 1, 'timestamp': -1}")
public class SparkAnalytics {
    
    @Id
    private String id;
    
    private String analysisType; // "sentiment", "trend", "correlation", "prediction"
    private LocalDateTime timestamp;
    private LocalDateTime dataStartTime;
    private LocalDateTime dataEndTime;
    
    private Map<String, Object> results;
    private Map<String, Double> metrics; // accuracy, precision, recall, etc.
    private Map<String, Object> parameters;
    
    private String sparkJobId;
    private String sparkApplicationId;
    private ProcessingStatus status;
    
    public enum ProcessingStatus {
        PENDING, PROCESSING, COMPLETED, FAILED
    }
}
JAVA

# Repository MongoDB
cat > "${JAVA_DIR}/src/main/java/com/davtroweb/survey/repository/SurveyRepository.java" <<'JAVA'
package com.davtroweb.survey.repository;

import com.davtroweb.survey.model.SurveyResponse;
import org.springframework.data.mongodb.repository.MongoRepository;
import org.springframework.data.mongodb.repository.Query;
import org.springframework.stereotype.Repository;
import java.time.LocalDateTime;
import java.util.List;
import java.util.Map;

@Repository
public interface SurveyRepository extends MongoRepository<SurveyResponse, String> {
    
    List<SurveyResponse> findBySurveyId(String surveyId);
    
    @Query("{'submittedAt': {$gte: ?0, $lte: ?1}}")
    List<SurveyResponse> findByDateRange(LocalDateTime start, LocalDateTime end);
    
    @Query("{'surveyId': ?0, 'answers.?1': ?2}")
    List<SurveyResponse> findByAnswerValue(String surveyId, String questionKey, Object value);
    
    @Query(value = "{'surveyId': ?0}", count = true)
    long countBySurveyId(String surveyId);
    
    @Query(value = "{}", fields = "{'answers': 1, 'submittedAt': 1}")
    List<Map<String, Object>> findAllForAnalytics();
}
JAVA

# Controller REST API
cat > "${JAVA_DIR}/src/main/java/com/davtroweb/survey/controller/SurveyController.java" <<'JAVA'
package com.davtroweb.survey.controller;

import com.davtroweb.survey.model.SurveyResponse;
import com.davtroweb.survey.repository.SurveyRepository;
import com.davtroweb.survey.service.SparkService;
import com.davtroweb.survey.service.ElkService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import javax.servlet.http.HttpServletRequest;
import java.time.LocalDateTime;
import java.util.*;
import java.util.stream.Collectors;

@Slf4j
@RestController
@RequestMapping("/api/survey")
@RequiredArgsConstructor
@CrossOrigin(origins = "*")
public class SurveyController {
    
    private final SurveyRepository surveyRepository;
    private final SparkService sparkService;
    private final ElkService elkService;
    
    @GetMapping("/questions")
    public ResponseEntity<List<Map<String, Object>>> getQuestions() {
        List<Map<String, Object>> questions = new ArrayList<>();
        
        questions.add(Map.of(
            "id", "spring_performance",
            "text", "Jak oceniasz wydajność Spring Boot API?",
            "type", "rating",
            "options", Arrays.asList("1 - Słabo", "2", "3", "4", "5 - Doskonale"),
            "category", "performance"
        ));
        
        questions.add(Map.of(
            "id", "java_tech_interest",
            "text", "Która technologia Java Cię interesuje?",
            "type", "multiselect",
            "options", Arrays.asList("Spring Boot", "Apache Spark", "Hibernate", "MongoDB", "Kafka Streams", "Quarkus", "Micronaut"),
            "category", "technology"
        ));
        
        questions.add(Map.of(
            "id", "integration_quality",
            "text", "Jak oceniasz integrację z Python/FastAPI?",
            "type", "rating",
            "options", Arrays.asList("1 - Słaba", "2", "3", "4", "5 - Doskonała"),
            "category", "integration"
        ));
        
        questions.add(Map.of(
            "id", "elk_usefulness",
            "text", "Czy uważasz, że ELK Stack jest przydatny?",
            "type", "choice",
            "options", Arrays.asList("Tak, zdecydowanie", "Raczej tak", "Nie wiem", "Raczej nie", "Nie"),
            "category", "monitoring"
        ));
        
        questions.add(Map.of(
            "id", "architecture_suggestions",
            "text", "Twoje sugestie dotyczące architektury:",
            "type", "text",
            "placeholder", "Podziel się swoimi pomysłami...",
            "category", "feedback"
        ));
        
        return ResponseEntity.ok(questions);
    }
    
    @PostMapping("/submit")
    public ResponseEntity<Map<String, Object>> submitSurvey(
            @RequestBody Map<String, Object> request,
            HttpServletRequest httpRequest) {
        
        try {
            String surveyId = "spring_js_survey_v1";
            String sessionId = httpRequest.getSession().getId();
            String userId = (String) request.getOrDefault("userId", "anonymous");
            
            @SuppressWarnings("unchecked")
            List<Map<String, Object>> responses = (List<Map<String, Object>>) request.get("responses");
            
            // Przygotuj odpowiedzi jako mapa
            Map<String, Object> answers = new HashMap<>();
            for (Map<String, Object> response : responses) {
                String questionId = (String) response.get("questionId");
                Object answer = response.get("answer");
                answers.put(questionId, answer);
            }
            
            // Metadane
            SurveyResponse.SurveyMetadata metadata = new SurveyResponse.SurveyMetadata();
            metadata.setSurveyType("spring_js_hybrid");
            metadata.setBrowser(httpRequest.getHeader("User-Agent"));
            metadata.setIpAddress(httpRequest.getRemoteAddr());
            metadata.setUserAgent(httpRequest.getHeader("User-Agent"));
            metadata.setReferer(httpRequest.getHeader("Referer"));
            
            Map<String, Object> techData = new HashMap<>();
            techData.put("javaVersion", System.getProperty("java.version"));
            techData.put("springVersion", "3.1.0");
            techData.put("timestamp", System.currentTimeMillis());
            metadata.setTechnicalData(techData);
            
            // Zapisz w MongoDB
            SurveyResponse surveyResponse = new SurveyResponse();
            surveyResponse.setSurveyId(surveyId);
            surveyResponse.setUserId(userId);
            surveyResponse.setSessionId(sessionId);
            surveyResponse.setAnswers(answers);
            surveyResponse.setMetadata(metadata);
            surveyResponse.setSubmittedAt(LocalDateTime.now());
            
            surveyRepository.save(surveyResponse);
            
            // Wyślij do Kafka dla Spark
            sparkService.sendToKafka(surveyResponse);
            
            // Wyślij do ELK
            elkService.logSurveySubmission(surveyResponse);
            
            log.info("Survey submitted successfully: sessionId={}, responses={}", sessionId, responses.size());
            
            return ResponseEntity.ok(Map.of(
                "success", true,
                "message", "Ankieta została przesłana!",
                "surveyId", surveyId,
                "timestamp", LocalDateTime.now().toString()
            ));
            
        } catch (Exception e) {
            log.error("Error submitting survey", e);
            return ResponseEntity.internalServerError().body(Map.of(
                "success", false,
                "error", e.getMessage()
            ));
        }
    }
    
    @GetMapping("/stats")
    public ResponseEntity<Map<String, Object>> getStats() {
        try {
            List<SurveyResponse> allResponses = surveyRepository.findAll();
            
            // Podstawowe statystyki
            long totalResponses = allResponses.size();
            
            // Oblicz średnią ocenę
            double avgRating = allResponses.stream()
                .filter(r -> r.getAnswers().containsKey("spring_performance"))
                .mapToInt(r -> {
                    Object answer = r.getAnswers().get("spring_performance");
                    if (answer instanceof String) {
                        String str = (String) answer;
                        if (str.contains("1")) return 1;
                        if (str.contains("2")) return 2;
                        if (str.contains("3")) return 3;
                        if (str.contains("4")) return 4;
                        if (str.contains("5")) return 5;
                    }
                    return 0;
                })
                .average()
                .orElse(0.0);
            
            // Unikalni użytkownicy
            long uniqueUsers = allResponses.stream()
                .map(SurveyResponse::getSessionId)
                .distinct()
                .count();
            
            // Popularność technologii
            Map<String, Long> techPopularity = allResponses.stream()
                .filter(r -> r.getAnswers().containsKey("java_tech_interest"))
                .flatMap(r -> {
                    Object answer = r.getAnswers().get("java_tech_interest");
                    if (answer instanceof List) {
                        @SuppressWarnings("unchecked")
                        List<String> techs = (List<String>) answer;
                        return techs.stream();
                    } else if (answer instanceof String) {
                        return Arrays.stream(((String) answer).split(","));
                    }
                    return Stream.empty();
                })
                .collect(Collectors.groupingBy(
                    tech -> tech.trim(),
                    Collectors.counting()
                ));
            
            // Przygotuj dane dla wykresów
            Map<String, Object> charts = new HashMap<>();
            
            // Wykres ocen
            Map<String, Object> ratingsChart = new HashMap<>();
            ratingsChart.put("labels", Arrays.asList("1", "2", "3", "4", "5"));
            ratingsChart.put("datasets", List.of(Map.of(
                "label", "Oceny wydajności Spring Boot",
                "data", Arrays.asList(10, 15, 30, 25, 20),
                "backgroundColor", "rgba(59, 130, 246, 0.5)"
            )));
            charts.put("ratings", ratingsChart);
            
            // Wykres technologii
            Map<String, Object> techChart = new HashMap<>();
            techChart.put("labels", new ArrayList<>(techPopularity.keySet()));
            techChart.put("datasets", List.of(Map.of(
                "label", "Popularność technologii",
                "data", new ArrayList<>(techPopularity.values()),
                "backgroundColor", Arrays.asList(
                    "#3B82F6", "#10B981", "#F59E0B", "#EF4444", "#8B5CF6", "#EC4899", "#06B6D4"
                )
            )));
            charts.put("technologies", techChart);
            
            Map<String, Object> response = new HashMap<>();
            response.put("totalResponses", totalResponses);
            response.put("avgRating", Math.round(avgRating * 10) / 10.0);
            response.put("uniqueUsers", uniqueUsers);
            response.put("techPopularity", techPopularity);
            response.put("charts", charts);
            response.put("lastUpdated", LocalDateTime.now().toString());
            
            return ResponseEntity.ok(response);
            
        } catch (Exception e) {
            log.error("Error generating stats", e);
            return ResponseEntity.internalServerError().body(Map.of(
                "error", e.getMessage()
            ));
        }
    }
    
    @GetMapping("/spark/status")
    public ResponseEntity<Map<String, Object>> getSparkStatus() {
        return ResponseEntity.ok(sparkService.getSparkStatus());
    }
    
    @PostMapping("/spark/trigger")
    public ResponseEntity<Map<String, Object>> triggerSparkJob(
            @RequestParam String jobType) {
        try {
            Map<String, Object> result = sparkService.triggerSparkJob(jobType);
            return ResponseEntity.ok(result);
        } catch (Exception e) {
            return ResponseEntity.badRequest().body(Map.of(
                "error", e.getMessage()
            ));
        }
    }
}
JAVA

# Service dla Spark
cat > "${JAVA_DIR}/src/main/java/com/davtroweb/survey/service/SparkService.java" <<'JAVA'
package com.davtroweb.survey.service;

import com.davtroweb.survey.model.SurveyResponse;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.kafka.core.KafkaTemplate;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestTemplate;
import java.util.HashMap;
import java.util.Map;

@Slf4j
@Service
@RequiredArgsConstructor
public class SparkService {
    
    private final KafkaTemplate<String, Object> kafkaTemplate;
    private final RestTemplate restTemplate;
    
    private static final String KAFKA_TOPIC = "survey-events";
    private static final String SPARK_MASTER_URL = "http://spark-master:8080";
    
    public void sendToKafka(SurveyResponse surveyResponse) {
        try {
            Map<String, Object> event = new HashMap<>();
            event.put("type", "SURVEY_SUBMITTED");
            event.put("surveyId", surveyResponse.getSurveyId());
            event.put("userId", surveyResponse.getUserId());
            event.put("timestamp", System.currentTimeMillis());
            event.put("data", surveyResponse.getAnswers());
            
            kafkaTemplate.send(KAFKA_TOPIC, surveyResponse.getSurveyId(), event);
            log.info("Sent survey to Kafka: surveyId={}", surveyResponse.getSurveyId());
            
        } catch (Exception e) {
            log.error("Error sending to Kafka", e);
        }
    }
    
    public Map<String, Object> getSparkStatus() {
        Map<String, Object> status = new HashMap<>();
        
        try {
            // Sprawdź status Spark Master
            String response = restTemplate.getForObject(
                SPARK_MASTER_URL + "/api/v1/applications", 
                String.class
            );
            
            status.put("sparkMaster", "RUNNING");
            status.put("applications", response);
            
        } catch (Exception e) {
            log.warn("Spark master not available", e);
            status.put("sparkMaster", "UNAVAILABLE");
            status.put("error", e.getMessage());
        }
        
        status.put("timestamp", System.currentTimeMillis());
        return status;
    }
    
    public Map<String, Object> triggerSparkJob(String jobType) {
        Map<String, Object> result = new HashMap<>();
        
        try {
            // Tutaj można dodać wywołanie REST API Spark do uruchomienia zadania
            // lub wysłać wiadomość do Kafka, którą Spark Stream będzie nasłuchiwał
            
            Map<String, String> jobRequest = new HashMap<>();
            jobRequest.put("jobType", jobType);
            jobRequest.put("triggeredBy", "spring-boot");
            jobRequest.put("timestamp", String.valueOf(System.currentTimeMillis()));
            
            kafkaTemplate.send("spark-jobs", jobType, jobRequest);
            
            result.put("success", true);
            result.put("message", "Spark job triggered: " + jobType);
            result.put("jobId", "job_" + System.currentTimeMillis());
            
        } catch (Exception e) {
            log.error("Error triggering Spark job", e);
            result.put("success", false);
            result.put("error", e.getMessage());
        }
        
        return result;
    }
}
JAVA

# Service dla ELK
cat > "${JAVA_DIR}/src/main/java/com/davtroweb/survey/service/ElkService.java" <<'JAVA'
package com.davtroweb.survey.service;

import com.davtroweb.survey.model.SurveyResponse;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.*;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestTemplate;
import java.util.HashMap;
import java.util.Map;

@Slf4j
@Service
@RequiredArgsConstructor
public class ElkService {
    
    private final RestTemplate restTemplate;
    
    private static final String ELASTICSEARCH_URL = "http://elasticsearch:9200";
    private static final String LOGSTASH_URL = "http://logstash:5000";
    
    public void logSurveySubmission(SurveyResponse surveyResponse) {
        try {
            // Przygotuj dokument dla Elasticsearch
            Map<String, Object> logEntry = new HashMap<>();
            logEntry.put("@timestamp", System.currentTimeMillis());
            logEntry.put("level", "INFO");
            logEntry.put("logger", "SurveyController");
            logEntry.put("message", "Survey submitted: " + surveyResponse.getSurveyId());
            logEntry.put("surveyId", surveyResponse.getSurveyId());
            logEntry.put("userId", surveyResponse.getUserId());
            logEntry.put("sessionId", surveyResponse.getSessionId());
            logEntry.put("responseCount", surveyResponse.getAnswers().size());
            logEntry.put("source", "spring-boot");
            
            // Wyślij do Elasticsearch
            HttpHeaders headers = new HttpHeaders();
            headers.setContentType(MediaType.APPLICATION_JSON);
            
            HttpEntity<Map<String, Object>> request = new HttpEntity<>(logEntry, headers);
            
            ResponseEntity<String> response = restTemplate.postForEntity(
                ELASTICSEARCH_URL + "/logs/_doc",
                request,
                String.class
            );
            
            if (response.getStatusCode().is2xxSuccessful()) {
                log.debug("Log sent to Elasticsearch: surveyId={}", surveyResponse.getSurveyId());
            }
            
            // Równolegle wyślij do Logstash (jeśli potrzebne)
            try {
                restTemplate.postForEntity(
                    LOGSTASH_URL,
                    request,
                    String.class
                );
            } catch (Exception e) {
                log.debug("Logstash not available, skipping");
            }
            
        } catch (Exception e) {
            log.error("Error sending log to ELK", e);
        }
    }
    
    public Map<String, Object> searchLogs(String query, int size) {
        Map<String, Object> result = new HashMap<>();
        
        try {
            // Przygotuj zapytanie Elasticsearch
            Map<String, Object> searchQuery = new HashMap<>();
            searchQuery.put("query", Map.of(
                "match", Map.of("message", query)
            ));
            searchQuery.put("size", size);
            searchQuery.put("sort", List.of(
                Map.of("@timestamp", Map.of("order", "desc"))
            ));
            
            HttpHeaders headers = new HttpHeaders();
            headers.setContentType(MediaType.APPLICATION_JSON);
            
            HttpEntity<Map<String, Object>> request = new HttpEntity<>(searchQuery, headers);
            
            ResponseEntity<Map> response = restTemplate.postForEntity(
                ELASTICSEARCH_URL + "/logs/_search",
                request,
                Map.class
            );
            
            if (response.getStatusCode().is2xxSuccessful()) {
                result.put("success", true);
                result.put("data", response.getBody());
            } else {
                result.put("success", false);
                result.put("error", "Elasticsearch query failed");
            }
            
        } catch (Exception e) {
            log.error("Error searching logs", e);
            result.put("success", false);
            result.put("error", e.getMessage());
        }
        
        return result;
    }
}
JAVA

# Konfiguracja Spring
cat > "${JAVA_DIR}/src/main/resources/application.yml" <<'YAML'
server:
  port: 8080
  servlet:
    context-path: /
    
spring:
  application:
    name: survey-spring-app
  
  data:
    mongodb:
      uri: mongodb://mongodb:27017/survey_db
      auto-index-creation: true
  
  kafka:
    bootstrap-servers: kafka:9092
    producer:
      key-serializer: org.apache.kafka.common.serialization.StringSerializer
      value-serializer: org.springframework.kafka.support.serializer.JsonSerializer
      properties:
        spring.json.type.mapping: surveyResponse:com.davtroweb.survey.model.SurveyResponse
    consumer:
      key-deserializer: org.apache.kafka.common.serialization.StringDeserializer
      value-deserializer: org.springframework.kafka.support.serializer.JsonDeserializer
      properties:
        spring.json.type.mapping: surveyResponse:com.davtroweb.survey.model.SurveyResponse
        spring.json.trusted.packages: "*"
  
  jackson:
    time-zone: UTC
    date-format: com.fasterxml.jackson.databind.util.ISO8601DateFormat

management:
  endpoints:
    web:
      exposure:
        include: health,info,metrics,prometheus
  metrics:
    export:
      prometheus:
        enabled: true

logging:
  level:
    com.davtroweb.survey: DEBUG
    org.springframework.kafka: INFO
    org.apache.kafka: INFO
  pattern:
    console: "%d{yyyy-MM-dd HH:mm:ss} [%thread] %-5level %logger{36} - %msg%n"
  file:
    name: /var/log/spring-survey.log

elk:
  enabled: true
  elasticsearch:
    url: http://elasticsearch:9200
  logstash:
    url: http://logstash:5000

spark:
  master: spark://spark-master:7077
  streaming:
    enabled: true
    checkpoint-dir: /tmp/spark-checkpoints
YAML

# Dockerfile dla Spring Boot
cat > "${JAVA_DIR}/Dockerfile" <<'DOCKER'
FROM eclipse-temurin:17-jdk-alpine as builder
WORKDIR /app
COPY .mvn/ .mvn
COPY mvnw pom.xml ./
RUN ./mvnw dependency:go-offline
COPY src ./src
RUN ./mvnw clean package -DskipTests

FROM eclipse-temurin:17-jre-alpine
WORKDIR /app
COPY --from=builder /app/target/*.jar app.jar
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "app.jar"]
DOCKER

# ========== 5. DODANIE ZADAŃ APACHE SPARK ==========

mkdir_p "${SPARK_DIR}/src/main/scala/com/davtroweb/analytics"

# Główne zadanie Spark
cat > "${SPARK_DIR}/src/main/scala/com/davtroweb/analytics/SurveyAnalytics.scala" <<'SCALA'
package com.davtroweb.analytics

import org.apache.spark.sql.SparkSession
import org.apache.spark.sql.functions._
import org.apache.spark.sql.types._
import org.apache.spark.sql.streaming.{OutputMode, Trigger}
import org.apache.spark.sql.{Dataset, Row}
import java.time.LocalDateTime
import scala.collection.JavaConverters._

object SurveyAnalytics {
  
  def main(args: Array[String]): Unit = {
    
    val spark = SparkSession.builder()
      .appName("SurveyAnalytics")
      .master("spark://spark-master:7077")
      .config("spark.sql.warehouse.dir", "/tmp/spark-warehouse")
      .config("spark.serializer", "org.apache.spark.serializer.KryoSerializer")
      .config("spark.kryoserializer.buffer.max", "512m")
      .getOrCreate()
    
    import spark.implicits._
    
    // Schemat danych ankietowych
    val surveySchema = StructType(Array(
      StructField("surveyId", StringType, nullable = false),
      StructField("userId", StringType, nullable = true),
      StructField("sessionId", StringType, nullable = false),
      StructField("answers", MapType(StringType, StringType), nullable = false),
      StructField("submittedAt", TimestampType, nullable = false),
      StructField("metadata", StructType(Array(
        StructField("surveyType", StringType, nullable = true),
        StructField("browser", StringType, nullable = true),
        StructField("ipAddress", StringType, nullable = true)
      )))
    ))
    
    // Czytaj dane z Kafka
    val kafkaStream = spark.readStream
      .format("kafka")
      .option("kafka.bootstrap.servers", "kafka:9092")
      .option("subscribe", "survey-events")
      .option("startingOffsets", "latest")
      .load()
    
    // Przetwórz dane JSON
    val surveyStream = kafkaStream
      .select(from_json(col("value").cast("string"), surveySchema).as("data"))
      .select("data.*")
    
    // 1. Analiza sentymentu odpowiedzi tekstowych
    val textAnalysis = surveyStream
      .filter(col("answers").getItem("architecture_suggestions").isNotNull)
      .select(
        col("surveyId"),
        col("userId"),
        col("answers").getItem("architecture_suggestions").as("suggestion"),
        col("submittedAt")
      )
      .withColumn("suggestion_length", length(col("suggestion")))
      .withColumn("suggestion_words", size(split(col("suggestion"), " ")))
      .withColumn("sentiment_score", 
        when(col("suggestion").contains("dobr") || col("suggestion").contains("super") || 
             col("suggestion").contains("świetn"), 1.0)
        .when(col("suggestion").contains("kieps") || col("suggestion").contains("słab") || 
              col("suggestion").contains("problem"), -1.0)
        .otherwise(0.0)
      )
    
    // 2. Agregacje ocen
    val ratingAnalysis = surveyStream
      .filter(col("answers").getItem("spring_performance").isNotNull)
      .select(
        col("surveyId"),
        col("answers").getItem("spring_performance").as("rating"),
        col("submittedAt")
      )
      .withColumn("rating_numeric", 
        when(col("rating").contains("1"), 1)
        .when(col("rating").contains("2"), 2)
        .when(col("rating").contains("3"), 3)
        .when(col("rating").contains("4"), 4)
        .when(col("rating").contains("5"), 5)
        .otherwise(0)
      )
      .groupBy(window(col("submittedAt"), "5 minutes").as("window"))
      .agg(
        count("*").as("total_responses"),
        avg("rating_numeric").as("avg_rating"),
        stddev("rating_numeric").as("rating_stddev"),
        collect_list("rating_numeric").as("all_ratings")
      )
    
    // 3. Analiza popularności technologii
    val techAnalysis = surveyStream
      .filter(col("answers").getItem("java_tech_interest").isNotNull)
      .select(
        explode(split(col("answers").getItem("java_tech_interest"), ",")).as("technology"),
        col("submittedAt")
      )
      .withColumn("technology_clean", trim(col("technology")))
      .groupBy(col("technology_clean"))
      .agg(
        count("*").as("total_votes"),
        countDistinct("submittedAt").as("unique_sessions")
      )
      .orderBy(desc("total_votes"))
    
    // 4. Zapisz wyniki do MongoDB
    val query1 = textAnalysis.writeStream
      .outputMode(OutputMode.Append())
      .foreachBatch { (batchDF: Dataset[Row], batchId: Long) =>
        batchDF.write
          .format("mongo")
          .mode("append")
          .option("uri", "mongodb://mongodb:27017")
          .option("database", "survey_analytics")
          .option("collection", "text_analysis")
          .save()
      }
      .trigger(Trigger.ProcessingTime("30 seconds"))
      .start()
    
    val query2 = ratingAnalysis.writeStream
      .outputMode(OutputMode.Update())
      .foreachBatch { (batchDF: Dataset[Row], batchId: Long) =>
        batchDF.write
          .format("mongo")
          .mode("append")
          .option("uri", "mongodb://mongodb:27017")
          .option("database", "survey_analytics")
          .option("collection", "rating_analysis")
          .save()
      }
      .trigger(Trigger.ProcessingTime("1 minute"))
      .start()
    
    val query3 = techAnalysis.writeStream
      .outputMode(OutputMode.Complete())
      .foreachBatch { (batchDF: Dataset[Row], batchId: Long) =>
        batchDF.write
          .format("mongo")
          .mode("overwrite")
          .option("uri", "mongodb://mongodb:27017")
          .option("database", "survey_analytics")
          .option("collection", "tech_popularity")
          .save()
      }
      .trigger(Trigger.ProcessingTime("2 minutes"))
      .start()
    
    // 5. Zapisz logi do Elasticsearch
    val elkStream = surveyStream
      .select(
        lit("survey_event").as("type"),
        col("surveyId"),
        col("userId"),
        col("sessionId"),
        col("submittedAt"),
        to_json(col("answers")).as("answers_json"),
        lit(LocalDateTime.now().toString).as("@timestamp")
      )
    
    val query4 = elkStream.writeStream
      .outputMode(OutputMode.Append())
      .format("org.elasticsearch.spark.sql")
      .option("es.nodes", "elasticsearch")
      .option("es.port", "9200")
      .option("es.resource", "spark_surveys/_doc")
      .option("checkpointLocation", "/tmp/elk-checkpoint")
      .trigger(Trigger.ProcessingTime("10 seconds"))
      .start()
    
    // Czekaj na zakończenie
    spark.streams.awaitAnyTermination()
  }
}
SCALA

# Zadanie batch Spark
cat > "${SPARK_DIR}/src/main/scala/com/davtroweb/analytics/BatchAnalytics.scala" <<'SCALA'
package com.davtroweb.analytics

import org.apache.spark.sql.SparkSession
import org.apache.spark.sql.functions._
import org.apache.spark.sql.expressions.Window
import java.time.LocalDateTime
import java.time.format.DateTimeFormatter

object BatchAnalytics {
  
  def main(args: Array[String]): Unit = {
    
    val spark = SparkSession.builder()
      .appName("BatchSurveyAnalytics")
      .master("spark://spark-master:7077")
      .config("spark.mongodb.input.uri", "mongodb://mongodb:27017/survey_db.survey_responses")
      .config("spark.mongodb.output.uri", "mongodb://mongodb:27017/survey_analytics")
      .getOrCreate()
    
    import spark.implicits._
    
    // Czytaj dane z MongoDB
    val surveyDF = spark.read
      .format("mongo")
      .option("database", "survey_db")
      .option("collection", "survey_responses")
      .load()
    
    // 1. Dzienne statystyki
    val dailyStats = surveyDF
      .withColumn("date", to_date($"submittedAt"))
      .groupBy($"date")
      .agg(
        count("*").as("total_submissions"),
        countDistinct($"userId").as("unique_users"),
        countDistinct($"sessionId").as("unique_sessions"),
        avg(when($"answers.spring_performance".contains("5"), 5)
          .when($"answers.spring_performance".contains("4"), 4)
          .when($"answers.spring_performance".contains("3"), 3)
          .when($"answers.spring_performance".contains("2"), 2)
          .when($"answers.spring_performance".contains("1"), 1)
          .otherwise(0)).as("avg_rating")
      )
      .orderBy(desc("date"))
    
    // 2. Analiza trendów technologicznych
    val techTrends = surveyDF
      .filter($"answers.java_tech_interest".isNotNull)
      .withColumn("technology", explode(split($"answers.java_tech_interest", ",")))
      .withColumn("technology_clean", trim($"technology"))
      .withColumn("date", to_date($"submittedAt"))
      .groupBy($"date", $"technology_clean")
      .agg(count("*").as("daily_votes"))
      .orderBy(desc("date"), desc("daily_votes"))
    
    // 3. Korelacje między odpowiedziami
    val correlations = surveyDF
      .select(
        when($"answers.spring_performance".contains("5"), 5)
          .when($"answers.spring_performance".contains("4"), 4)
          .when($"answers.spring_performance".contains("3"), 3)
          .when($"answers.spring_performance".contains("2"), 2)
          .when($"answers.spring_performance".contains("1"), 1)
          .otherwise(0).as("spring_rating"),
        when($"answers.integration_quality".contains("5"), 5)
          .when($"answers.integration_quality".contains("4"), 4)
          .when($"answers.integration_quality".contains("3"), 3)
          .when($"answers.integration_quality".contains("2"), 2)
          .when($"answers.integration_quality".contains("1"), 1)
          .otherwise(0).as("integration_rating"),
        when($"answers.elk_usefulness".contains("Tak, zdecydowanie"), 2)
          .when($"answers.elk_usefulness".contains("Raczej tak"), 1)
          .when($"answers.elk_usefulness".contains("Raczej nie"), -1)
          .when($"answers.elk_usefulness".contains("Nie"), -2)
          .otherwise(0).as("elk_sentiment")
      )
      .na.drop()
      .agg(
        corr("spring_rating", "integration_rating").as("spring_integration_corr"),
        corr("spring_rating", "elk_sentiment").as("spring_elk_corr"),
        corr("integration_rating", "elk_sentiment").as("integration_elk_corr")
      )
    
    // 4. Raport godzinowy
    val hourlyReport = surveyDF
      .withColumn("hour", hour($"submittedAt"))
      .groupBy($"hour")
      .agg(
        count("*").as("submissions"),
        countDistinct($"userId").as("users"),
        avg(when($"answers.spring_performance".contains("5"), 5)
          .when($"answers.spring_performance".contains("4"), 4)
          .otherwise(3)).as("avg_rating")
      )
      .orderBy("hour")
    
    // 5. Zapisz wyniki do MongoDB
    dailyStats.write
      .format("mongo")
      .mode("overwrite")
      .option("database", "survey_analytics")
      .option("collection", "daily_stats")
      .save()
    
    techTrends.write
      .format("mongo")
      .mode("overwrite")
      .option("database", "survey_analytics")
      .option("collection", "tech_trends")
      .save()
    
    correlations.write
      .format("mongo")
      .mode("overwrite")
      .option("database", "survey_analytics")
      .option("collection", "correlations")
      .save()
    
    hourlyReport.write
      .format("mongo")
      .mode("overwrite")
      .option("database", "survey_analytics")
      .option("collection", "hourly_report")
      .save()
    
    // 6. Wygeneruj raport do Elasticsearch
    val reportTimestamp = LocalDateTime.now()
      .format(DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm:ss"))
    
    val finalReport = spark.createDataFrame(Seq(
      (reportTimestamp, dailyStats.count(), hourlyReport.count(), 
       correlations.first().getAs[Double]("spring_integration_corr"))
    )).toDF("generated_at", "total_days", "total_hours", "avg_correlation")
    
    finalReport.write
      .format("org.elasticsearch.spark.sql")
      .option("es.nodes", "elasticsearch")
      .option("es.port", "9200")
      .option("es.resource", "survey_reports/_doc")
      .save()
    
    spark.stop()
  }
}
SCALA

# Build dla Spark
cat > "${SPARK_DIR}/build.sbt" <<'SBT'
name := "survey-spark-analytics"
version := "1.0.0"
scalaVersion := "2.12.15"

val sparkVersion = "3.4.0"

libraryDependencies ++= Seq(
  "org.apache.spark" %% "spark-core" % sparkVersion % "provided",
  "org.apache.spark" %% "spark-sql" % sparkVersion % "provided",
  "org.apache.spark" %% "spark-streaming" % sparkVersion % "provided",
  "org.apache.spark" %% "spark-sql-kafka-0-10" % sparkVersion,
  "org.apache.spark" %% "spark-streaming-kafka-0-10" % sparkVersion,
  "org.mongodb.spark" %% "mongo-spark-connector" % "10.1.1",
  "org.elasticsearch" %% "elasticsearch-spark-30" % "8.10.2",
  "com.fasterxml.jackson.core" % "jackson-databind" % "2.15.2",
  "com.fasterxml.jackson.module" %% "jackson-module-scala" % "2.15.2"
)

assemblyMergeStrategy in assembly := {
  case PathList("META-INF", xs @ _*) => MergeStrategy.discard
  case x => MergeStrategy.first
}
SBT

# ========== 6. DODANIE ELK STACK MANIFESTS ==========

mkdir_p "${ELK_DIR}"

# Elasticsearch
cat > "${MANIFESTS_DIR}/elasticsearch.yaml" <<'YAML'
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: elasticsearch
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: elasticsearch
spec:
  serviceName: elasticsearch
  replicas: 1
  selector:
    matchLabels:
      app: ${PROJECT}
      component: elasticsearch
  template:
    metadata:
      labels:
        app: ${PROJECT}
        component: elasticsearch
    spec:
      initContainers:
        - name: fix-permissions
          image: busybox:1.35
          command: ["sh", "-c", "chown -R 1000:1000 /usr/share/elasticsearch/data"]
          securityContext:
            privileged: true
          volumeMounts:
            - name: elasticsearch-data
              mountPath: /usr/share/elasticsearch/data
      containers:
        - name: elasticsearch
          image: elasticsearch:8.10.2
          env:
            - name: discovery.type
              value: single-node
            - name: ES_JAVA_OPTS
              value: "-Xms512m -Xmx512m"
            - name: xpack.security.enabled
              value: "false"
            - name: xpack.security.enrollment.enabled
              value: "false"
            - name: xpack.monitoring.collection.enabled
              value: "true"
          ports:
            - containerPort: 9200
              name: http
            - containerPort: 9300
              name: transport
          volumeMounts:
            - name: elasticsearch-data
              mountPath: /usr/share/elasticsearch/data
          resources:
            requests:
              cpu: "500m"
              memory: "1Gi"
            limits:
              cpu: "1000m"
              memory: "2Gi"
          readinessProbe:
            httpGet:
              path: /_cluster/health
              port: 9200
            initialDelaySeconds: 60
            periodSeconds: 10
  volumeClaimTemplates:
    - metadata:
        name: elasticsearch-data
      spec:
        accessModes: ["ReadWriteOnce"]
        resources:
          requests:
            storage: 10Gi
---
apiVersion: v1
kind: Service
metadata:
  name: elasticsearch
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: elasticsearch
spec:
  ports:
    - port: 9200
      targetPort: 9200
      name: http
    - port: 9300
      targetPort: 9300
      name: transport
  selector:
    app: ${PROJECT}
    component: elasticsearch
YAML

# Logstash
cat > "${MANIFESTS_DIR}/logstash.yaml" <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: logstash
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: logstash
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ${PROJECT}
      component: logstash
  template:
    metadata:
      labels:
        app: ${PROJECT}
        component: logstash
    spec:
      containers:
        - name: logstash
          image: logstash:8.10.2
          ports:
            - containerPort: 5000
              name: tcp
            - containerPort: 5001
              name: http
            - containerPort: 9600
              name: monitoring
          env:
            - name: XPACK_MONITORING_ENABLED
              value: "false"
          volumeMounts:
            - name: logstash-config
              mountPath: /usr/share/logstash/pipeline/
          resources:
            requests:
              cpu: "200m"
              memory: "512Mi"
            limits:
              cpu: "500m"
              memory: "1Gi"
          readinessProbe:
            tcpSocket:
              port: 9600
            initialDelaySeconds: 30
            periodSeconds: 10
      volumes:
        - name: logstash-config
          configMap:
            name: logstash-config
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: logstash-config
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: logstash
data:
  logstash.conf: |
    input {
      tcp {
        port => 5000
        codec => json
      }
      http {
        port => 5001
        codec => json
      }
      beats {
        port => 5044
      }
    }
    
    filter {
      if [type] == "survey" {
        mutate {
          add_field => { 
            "[@metadata][index]" => "surveys-%{+YYYY.MM.dd}"
          }
        }
      } else if [type] == "spark" {
        mutate {
          add_field => { 
            "[@metadata][index]" => "spark-%{+YYYY.MM.dd}"
          }
        }
      } else {
        mutate {
          add_field => { 
            "[@metadata][index]" => "logs-%{+YYYY.MM.dd}"
          }
        }
      }
      
      date {
        match => [ "timestamp", "ISO8601" ]
        target => "@timestamp"
      }
      
      mutate {
        remove_field => [ "timestamp" ]
      }
    }
    
    output {
      elasticsearch {
        hosts => ["elasticsearch:9200"]
        index => "%{[@metadata][index]}"
      }
      
      stdout {
        codec => rubydebug
      }
    }
---
apiVersion: v1
kind: Service
metadata:
  name: logstash
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: logstash
spec:
  ports:
    - port: 5000
      targetPort: 5000
      name: tcp
    - port: 5001
      targetPort: 5001
      name: http
    - port: 5044
      targetPort: 5044
      name: beats
  selector:
    app: ${PROJECT}
    component: logstash
YAML

# Kibana
cat > "${MANIFESTS_DIR}/kibana.yaml" <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: kibana
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: kibana
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ${PROJECT}
      component: kibana
  template:
    metadata:
      labels:
        app: ${PROJECT}
        component: kibana
    spec:
      containers:
        - name: kibana
          image: kibana:8.10.2
          ports:
            - containerPort: 5601
          env:
            - name: ELASTICSEARCH_HOSTS
              value: "http://elasticsearch:9200"
            - name: XPACK_MONITORING_ENABLED
              value: "true"
            - name: XPACK_SECURITY_ENABLED
              value: "false"
          resources:
            requests:
              cpu: "200m"
              memory: "512Mi"
            limits:
              cpu: "500m"
              memory: "1Gi"
          readinessProbe:
            httpGet:
              path: /api/status
              port: 5601
            initialDelaySeconds: 60
            periodSeconds: 10
---
apiVersion: v1
kind: Service
metadata:
  name: kibana
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: kibana
spec:
  ports:
    - port: 5601
      targetPort: 5601
  selector:
    app: ${PROJECT}
    component: kibana
YAML

# ========== 7. DODANIE MONGODB ==========

cat > "${MANIFESTS_DIR}/mongodb.yaml" <<'YAML'
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: mongodb
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: mongodb
spec:
  serviceName: mongodb
  replicas: 1
  selector:
    matchLabels:
      app: ${PROJECT}
      component: mongodb
  template:
    metadata:
      labels:
        app: ${PROJECT}
        component: mongodb
    spec:
      containers:
        - name: mongodb
          image: mongo:7.0
          ports:
            - containerPort: 27017
          env:
            - name: MONGO_INITDB_ROOT_USERNAME
              value: "admin"
            - name: MONGO_INITDB_ROOT_PASSWORD
              value: "adminpassword"
          volumeMounts:
            - name: mongodb-data
              mountPath: /data/db
          resources:
            requests:
              cpu: "500m"
              memory: "1Gi"
            limits:
              cpu: "1000m"
              memory: "2Gi"
          readinessProbe:
            exec:
              command:
                - mongosh
                - --eval
                - "db.adminCommand('ping')"
            initialDelaySeconds: 30
            periodSeconds: 10
  volumeClaimTemplates:
    - metadata:
        name: mongodb-data
      spec:
        accessModes: ["ReadWriteOnce"]
        resources:
          requests:
            storage: 10Gi
---
apiVersion: v1
kind: Service
metadata:
  name: mongodb
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: mongodb
spec:
  ports:
    - port: 27017
      targetPort: 27017
  selector:
    app: ${PROJECT}
    component: mongodb
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: mongodb-init
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: mongodb
data:
  init.js: |
    db = db.getSiblingDB('survey_db');
    
    db.createUser({
      user: 'survey_user',
      pwd: 'survey_password',
      roles: [
        { role: 'readWrite', db: 'survey_db' },
        { role: 'readWrite', db: 'survey_analytics' }
      ]
    });
    
    db.createCollection('survey_responses');
    db.survey_responses.createIndex({ surveyId: 1 });
    db.survey_responses.createIndex({ submittedAt: -1 });
    db.survey_responses.createIndex({ userId: 1 });
    
    db = db.getSiblingDB('survey_analytics');
    db.createCollection('text_analysis');
    db.createCollection('rating_analysis');
    db.createCollection('tech_popularity');
    db.createCollection('daily_stats');
    db.createCollection('tech_trends');
    db.createCollection('correlations');
    db.createCollection('hourly_report');
    
    print('MongoDB initialized successfully');
---
apiVersion: batch/v1
kind: Job
metadata:
  name: mongodb-init
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: mongodb-init
spec:
  template:
    metadata:
      labels:
        app: ${PROJECT}
        component: mongodb-init
    spec:
      restartPolicy: OnFailure
      initContainers:
        - name: wait-for-mongodb
          image: mongo:7.0
          command: ['mongosh', '--host', 'mongodb', '--eval', 'db.adminCommand("ping")']
      containers:
        - name: init
          image: mongo:7.0
          command: 
            - mongosh
            - --host
            - mongodb
            - --username
            - admin
            - --password
            - adminpassword
            - --authenticationDatabase
            - admin
            - /scripts/init.js
          volumeMounts:
            - name: init-script
              mountPath: /scripts
      volumes:
        - name: init-script
          configMap:
            name: mongodb-init
YAML

# ========== 8. DODANIE SPRING BOOT DEPLOYMENT ==========

cat > "${MANIFESTS_DIR}/spring-app-deployment.yaml" <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: spring-app
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: spring-app
spec:
  replicas: 2
  selector:
    matchLabels:
      app: ${PROJECT}
      component: spring-app
  template:
    metadata:
      labels:
        app: ${PROJECT}
        component: spring-app
    spec:
      initContainers:
        - name: wait-for-mongodb
          image: mongo:7.0
          command: ['mongosh', '--host', 'mongodb', '--eval', 'db.adminCommand("ping")']
        - name: wait-for-kafka
          image: confluentinc/cp-kafka:7.5.0
          command: 
            - sh
            - -c
            - |
              until kafka-broker-api-versions --bootstrap-server kafka:9092; do
                echo "Waiting for Kafka..."
                sleep 5
              done
        - name: wait-for-elasticsearch
          image: busybox:1.35
          command: 
            - sh
            - -c
            - |
              until wget -q -O- http://elasticsearch:9200; do
                echo "Waiting for Elasticsearch..."
                sleep 5
              done
      containers:
        - name: spring-app
          image: ghcr.io/exea-centrum/website-db-vault-kaf-redis-arg-kust-kyv-gra-loki-temp-pgui-spring:latest
          ports:
            - containerPort: 8080
          env:
            - name: SPRING_DATA_MONGODB_URI
              value: "mongodb://survey_user:survey_password@mongodb:27017/survey_db?authSource=survey_db"
            - name: SPRING_KAFKA_BOOTSTRAP_SERVERS
              value: "kafka:9092"
            - name: ELASTICSEARCH_URL
              value: "http://elasticsearch:9200"
            - name: LOGSTASH_URL
              value: "http://logstash:5000"
            - name: JAVA_OPTS
              value: "-Xms512m -Xmx512m -XX:+UseG1GC"
          resources:
            requests:
              cpu: "500m"
              memory: "1Gi"
            limits:
              cpu: "1000m"
              memory: "2Gi"
          livenessProbe:
            httpGet:
              path: /actuator/health
              port: 8080
            initialDelaySeconds: 120
            periodSeconds: 30
          readinessProbe:
            httpGet:
              path: /actuator/health/readiness
              port: 8080
            initialDelaySeconds: 30
            periodSeconds: 10
---
apiVersion: v1
kind: Service
metadata:
  name: spring-app-service
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: spring-app
spec:
  ports:
    - port: 8080
      targetPort: 8080
  selector:
    app: ${PROJECT}
    component: spring-app
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: spring-app-config
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: spring-app
data:
  application.yml: |
    spring:
      data:
        mongodb:
          uri: mongodb://survey_user:survey_password@mongodb:27017/survey_db?authSource=survey_db
          auto-index-creation: true
      
      kafka:
        bootstrap-servers: kafka:9092
        producer:
          key-serializer: org.apache.kafka.common.serialization.StringSerializer
          value-serializer: org.springframework.kafka.support.serializer.JsonSerializer
        consumer:
          group-id: spring-survey-group
          key-deserializer: org.apache.kafka.common.serialization.StringDeserializer
          value-deserializer: org.springframework.kafka.support.serializer.JsonDeserializer
          properties:
            spring.json.trusted.packages: "*"
    
    management:
      endpoints:
        web:
          exposure:
            include: health,info,metrics,prometheus
      metrics:
        export:
          prometheus:
            enabled: true
    
    logging:
      level:
        com.davtroweb: DEBUG
      file:
        name: /var/log/spring-app.log
    
    elk:
      elasticsearch-url: http://elasticsearch:9200
      logstash-url: http://logstash:5000
    
    spark:
      master-url: spark://spark-master:7077
YAML

# ========== 9. DODANIE SPARK DEPLOYMENT ==========

cat > "${MANIFESTS_DIR}/spark-master.yaml" <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: spark-master
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: spark-master
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ${PROJECT}
      component: spark-master
  template:
    metadata:
      labels:
        app: ${PROJECT}
        component: spark-master
    spec:
      initContainers:
        - name: wait-for-kafka
          image: confluentinc/cp-kafka:7.5.0
          command: 
            - sh
            - -c
            - |
              until kafka-broker-api-versions --bootstrap-server kafka:9092; do
                echo "Waiting for Kafka..."
                sleep 5
              done
        - name: wait-for-mongodb
          image: mongo:7.0
          command: ['mongosh', '--host', 'mongodb', '--eval', 'db.adminCommand("ping")']
      containers:
        - name: spark-master
          image: bitnami/spark:3.4.0
          ports:
            - containerPort: 7077
              name: master
            - containerPort: 8080
              name: webui
            - containerPort: 4040
              name: jobui
          env:
            - name: SPARK_MODE
              value: "master"
            - name: SPARK_MASTER_HOST
              value: "spark-master"
            - name: SPARK_MASTER_PORT
              value: "7077"
            - name: SPARK_MASTER_WEBUI_PORT
              value: "8080"
            - name: SPARK_RPC_AUTHENTICATION_ENABLED
              value: "no"
            - name: SPARK_RPC_ENCRYPTION_ENABLED
              value: "no"
            - name: SPARK_LOCAL_STORAGE_ENCRYPTION_ENABLED
              value: "no"
            - name: SPARK_SSL_ENABLED
              value: "no"
          resources:
            requests:
              cpu: "500m"
              memory: "2Gi"
            limits:
              cpu: "2000m"
              memory: "4Gi"
          readinessProbe:
            tcpSocket:
              port: 7077
            initialDelaySeconds: 60
            periodSeconds: 10
---
apiVersion: v1
kind: Service
metadata:
  name: spark-master
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: spark-master
spec:
  ports:
    - port: 7077
      targetPort: 7077
      name: master
    - port: 8080
      targetPort: 8080
      name: webui
  selector:
    app: ${PROJECT}
    component: spark-master
YAML

cat > "${MANIFESTS_DIR}/spark-worker.yaml" <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: spark-worker
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: spark-worker
spec:
  replicas: 2
  selector:
    matchLabels:
      app: ${PROJECT}
      component: spark-worker
  template:
    metadata:
      labels:
        app: ${PROJECT}
        component: spark-worker
    spec:
      initContainers:
        - name: wait-for-spark-master
          image: busybox:1.35
          command: 
            - sh
            - -c
            - |
              until nc -z spark-master 7077; do
                echo "Waiting for Spark Master..."
                sleep 5
              done
      containers:
        - name: spark-worker
          image: bitnami/spark:3.4.0
          ports:
            - containerPort: 8081
              name: webui
          env:
            - name: SPARK_MODE
              value: "worker"
            - name: SPARK_MASTER_URL
              value: "spark://spark-master:7077"
            - name: SPARK_WORKER_CORES
              value: "2"
            - name: SPARK_WORKER_MEMORY
              value: "2g"
            - name: SPARK_WORKER_WEBUI_PORT
              value: "8081"
            - name: SPARK_RPC_AUTHENTICATION_ENABLED
              value: "no"
            - name: SPARK_RPC_ENCRYPTION_ENABLED
              value: "no"
            - name: SPARK_LOCAL_STORAGE_ENCRYPTION_ENABLED
              value: "no"
            - name: SPARK_SSL_ENABLED
              value: "no"
          resources:
            requests:
              cpu: "1000m"
              memory: "2Gi"
            limits:
              cpu: "2000m"
              memory: "4Gi"
          readinessProbe:
            tcpSocket:
              port: 8081
            initialDelaySeconds: 60
            periodSeconds: 10
---
apiVersion: v1
kind: Service
metadata:
  name: spark-worker
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: spark-worker
spec:
  ports:
    - port: 8081
      targetPort: 8081
      name: webui
  selector:
    app: ${PROJECT}
    component: spark-worker
YAML

# ========== 10. AKTUALIZACJA INGRESS DLA NOWYCH KOMPONENTÓW ==========

cat > "${MANIFESTS_DIR}/ingress-extended.yaml" <<'YAML'
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: ${PROJECT}-ingress-extended
  namespace: ${NAMESPACE}
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
    nginx.ingress.kubernetes.io/ssl-redirect: "false"
    nginx.ingress.kubernetes.io/enable-cors: "true"
    nginx.ingress.kubernetes.io/cors-allow-origin: "*"
spec:
  rules:
  - host: app.${PROJECT}.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: fastapi-web-service
            port:
              number: 80
      - path: /new-survey
        pathType: Prefix
        backend:
          service:
            name: fastapi-web-service
            port:
              number: 80
      - path: /api/v2
        pathType: Prefix
        backend:
          service:
            name: fastapi-web-service
            port:
              number: 80
      - path: /api/spring
        pathType: Prefix
        backend:
          service:
            name: spring-app-service
            port:
              number: 8080
  
  - host: spring.${PROJECT}.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: spring-app-service
            port:
              number: 8080
  
  - host: spark.${PROJECT}.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: spark-master
            port:
              number: 8080
  
  - host: kibana.${PROJECT}.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: kibana
            port:
              number: 5601
  
  - host: grafana.${PROJECT}.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: grafana-service
            port:
              number: 80
  
  - host: pgadmin.${PROJECT}.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: pgadmin
            port:
              number: 80
  
  - host: kafka-ui.${PROJECT}.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: kafka-ui
            port:
              number: 8080
YAML

# ========== 11. DODANIE MONITORINGU DLA NOWYCH KOMPONENTÓW ==========

cat > "${MANIFESTS_DIR}/monitoring-extended.yaml" <<'YAML'
# Exporter dla MongoDB
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mongodb-exporter
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: mongodb-exporter
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ${PROJECT}
      component: mongodb-exporter
  template:
    metadata:
      labels:
        app: ${PROJECT}
        component: mongodb-exporter
    spec:
      containers:
        - name: mongodb-exporter
          image: percona/mongodb_exporter:0.39.0
          ports:
            - containerPort: 9216
          args:
            - --mongodb.uri=mongodb://admin:adminpassword@mongodb:27017
            - --collect.collection
            - --collect.database
            - --collect.indexusage
            - --collect.connpoolstats
          resources:
            requests:
              cpu: "100m"
              memory: "128Mi"
            limits:
              cpu: "200m"
              memory: "256Mi"
---
apiVersion: v1
kind: Service
metadata:
  name: mongodb-exporter
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: mongodb-exporter
spec:
  ports:
    - port: 9216
      targetPort: 9216
  selector:
    app: ${PROJECT}
    component: mongodb-exporter

# ServiceMonitor dla MongoDB
---
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: mongodb-monitor
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
spec:
  selector:
    matchLabels:
      app: ${PROJECT}
      component: mongodb-exporter
  endpoints:
  - port: http
    interval: 30s

# ServiceMonitor dla Spring Boot
---
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: spring-monitor
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
spec:
  selector:
    matchLabels:
      app: ${PROJECT}
      component: spring-app
  endpoints:
  - port: http
    path: /actuator/prometheus
    interval: 15s

# ServiceMonitor dla Elasticsearch
---
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: elasticsearch-monitor
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
spec:
  selector:
    matchLabels:
      app: ${PROJECT}
      component: elasticsearch
  endpoints:
  - port: http
    path: /_prometheus/metrics
    interval: 30s

# Dodatkowe dashbordy Grafana
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-dashboards-extended
  namespace: ${NAMESPACE}
data:
  spring-boot-dashboard.json: |-
    {
      "dashboard": {
        "title": "Spring Boot Metrics",
        "panels": [
          {
            "title": "HTTP Requests",
            "type": "graph",
            "targets": [
              {
                "expr": "rate(http_server_requests_seconds_count[5m])",
                "legendFormat": "{{method}} {{status}}"
              }
            ]
          }
        ]
      }
    }
  
  spark-dashboard.json: |-
    {
      "dashboard": {
        "title": "Apache Spark",
        "panels": [
          {
            "title": "Spark Applications",
            "type": "stat",
            "targets": [
              {
                "expr": "spark_running_applications",
                "legendFormat": "Running Apps"
              }
            ]
          }
        ]
      }
    }
  
  mongodb-dashboard.json: |-
    {
      "dashboard": {
        "title": "MongoDB Metrics",
        "panels": [
          {
            "title": "MongoDB Connections",
            "type": "stat",
            "targets": [
              {
                "expr": "mongodb_connections_current",
                "legendFormat": "Connections"
              }
            ]
          }
        ]
      }
    }
  
  elk-dashboard.json: |-
    {
      "dashboard": {
        "title": "ELK Stack",
        "panels": [
          {
            "title": "Elasticsearch Health",
            "type": "stat",
            "targets": [
              {
                "expr": "elasticsearch_cluster_health_status",
                "legendFormat": "{{cluster}}"
              }
            ]
          }
        ]
      }
    }
YAML

# ========== 12. AKTUALIZACJA KUSTOMIZATION ==========

cat > "${MANIFESTS_DIR}/kustomization-extended.yaml" <<'YAML'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: ${NAMESPACE}

resources:
  # Istniejące zasoby
  - postgres-db.yaml
  - postgres-clusterip.yaml
  - redis.yaml
  - vault.yaml
  - kafka-kraft.yaml
  - kafka-job-sa.yaml
  - kafka-topic-job.yaml
  - fastapi-config.yaml
  - app-deployment.yaml
  - message-processor.yaml
  - prometheus-config.yaml
  - postgres-exporter.yaml
  - kafka-exporter.yaml
  - node-exporter.yaml
  - service-monitors.yaml
  - prometheus.yaml
  - grafana-datasource.yaml
  - grafana-dashboards.yaml
  - grafana.yaml
  - loki-config.yaml
  - loki.yaml
  - promtail-config.yaml
  - promtail.yaml
  - tempo-config.yaml
  - tempo.yaml
  - pgadmin.yaml
  - kafka-ui.yaml
  - network-policies.yaml
  - ingress.yaml
  - kyverno-policy.yaml
  
  # Nowe zasoby
  - mongodb.yaml
  - elasticsearch.yaml
  - logstash.yaml
  - kibana.yaml
  - spring-app-deployment.yaml
  - spark-master.yaml
  - spark-worker.yaml
  - monitoring-extended.yaml
  - ingress-extended.yaml

# Common labels
commonLabels:
  app: ${PROJECT}
  app.kubernetes.io/name: ${PROJECT}
  app.kubernetes.io/instance: ${PROJECT}
  app.kubernetes.io/managed-by: kustomize

# Zmienne
vars:
  - name: NAMESPACE
    objref:
      kind: Namespace
      name: davtrowebdbvault
    fieldref:
      fieldpath: metadata.name
  - name: PROJECT
    objref:
      kind: ConfigMap
      name: fastapi-config
    fieldref:
      fieldpath: data.PROJECT
YAML

# ========== 13. AKTUALIZACJA GITHUB ACTIONS ==========

cat > "${PROJECT_DIR}/.github/workflows/ci-cd-extended.yaml" <<'YAML'
name: CI/CD Extended - Full Stack

on:
  push:
    branches: [main]
    paths:
      - 'app/**'
      - 'java-app/**'
      - 'spark-jobs/**'
      - 'manifests/**'
      - 'Dockerfile'
      - '.github/workflows/ci-cd-extended.yaml'
  workflow_dispatch:

jobs:
  build-python:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Build Python Docker image
        uses: docker/build-push-action@v4
        with:
          context: .
          push: true
          tags: |
            ghcr.io/exea-centrum/website-db-vault-kaf-redis-arg-kust-kyv-gra-loki-temp-pgui:latest
            ghcr.io/exea-centrum/website-db-vault-kaf-redis-arg-kust-kyv-gra-loki-temp-pgui:${{ github.sha }}
          cache-from: type=registry,ref=ghcr.io/exea-centrum/website-db-vault-kaf-redis-arg-kust-kyv-gra-loki-temp-pgui:latest
          cache-to: type=inline

  build-spring:
    runs-on: ubuntu-latest
    needs: build-python
    steps:
      - uses: actions/checkout@v4
      
      - name: Set up JDK 17
        uses: actions/setup-java@v3
        with:
          java-version: '17'
          distribution: 'temurin'
      
      - name: Build Spring Boot
        working-directory: ./java-app
        run: |
          chmod +x mvnw
          ./mvnw clean package -DskipTests
      
      - name: Build Spring Docker image
        uses: docker/build-push-action@v4
        with:
          context: ./java-app
          push: true
          tags: |
            ghcr.io/exea-centrum/website-db-vault-kaf-redis-arg-kust-kyv-gra-loki-temp-pgui-spring:latest
            ghcr.io/exea-centrum/website-db-vault-kaf-redis-arg-kust-kyv-gra-loki-temp-pgui-spring:${{ github.sha }}

  build-spark:
    runs-on: ubuntu-latest
    needs: build-spring
    steps:
      - uses: actions/checkout@v4
      
      - name: Set up Scala
        uses: olafurpg/setup-scala@v13
        with:
          java-version: adopt@1.11
      
      - name: Build Spark Jobs
        working-directory: ./spark-jobs
        run: |
          sbt assembly
      
      - name: Build Spark Docker image
        uses: docker/build-push-action@v4
        with:
          context: ./spark-jobs
          push: true
          tags: |
            ghcr.io/exea-centrum/website-db-vault-kaf-redis-arg-kust-kyv-gra-loki-temp-pgui-spark:latest
            ghcr.io/exea-centrum/website-db-vault-kaf-redis-arg-kust-kyv-gra-loki-temp-pgui-spark:${{ github.sha }}

  deploy:
    runs-on: ubuntu-latest
    needs: [build-python, build-spring, build-spark]
    environment: production
    steps:
      - uses: actions/checkout@v4
      
      - name: Configure Kustomize
        run: |
          cd manifests/base
          kustomize edit set image \
            ghcr.io/exea-centrum/website-db-vault-kaf-redis-arg-kust-kyv-gra-loki-temp-pgui=ghcr.io/exea-centrum/website-db-vault-kaf-redis-arg-kust-kyv-gra-loki-temp-pgui:${{ github.sha }} \
            ghcr.io/exea-centrum/website-db-vault-kaf-redis-arg-kust-kyv-gra-loki-temp-pgui-spring=ghcr.io/exea-centrum/website-db-vault-kaf-redis-arg-kust-kyv-gra-loki-temp-pgui-spring:${{ github.sha }}
      
      - name: Deploy to Kubernetes
        run: |
          kubectl apply -k manifests/base --namespace=davtrowebdbvault
          kubectl rollout status deployment/fastapi-web-app -n davtrowebdbvault --timeout=300s
          kubectl rollout status deployment/spring-app -n davtrowebdbvault --timeout=300s
          kubectl rollout status deployment/spark-master -n davtrowebdbvault --timeout=300s
          kubectl rollout status deployment/spark-worker -n davtrowebdbvault --timeout=300s
      
      - name: Verify Deployment
        run: |
          kubectl get pods -n davtrowebdbvault
          kubectl get svc -n davtrowebdbvault
YAML

# ========== 14. UTWORZENIE SKRYPTU DEPLOY ==========

cat > "${PROJECT_DIR}/deploy-extended.sh" <<'BASH'
#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAMESPACE="davtrowebdbvault"

echo "🚀 Deploying Extended Stack: Spring Boot + Spark + MongoDB + ELK"

# 1. Deploy new databases
echo "📦 Deploying MongoDB..."
kubectl apply -f "${PROJECT_DIR}/manifests/base/mongodb.yaml" -n "${NAMESPACE}"

echo "📦 Deploying ELK Stack..."
kubectl apply -f "${PROJECT_DIR}/manifests/base/elasticsearch.yaml" -n "${NAMESPACE}"
kubectl apply -f "${PROJECT_DIR}/manifests/base/logstash.yaml" -n "${NAMESPACE}"
kubectl apply -f "${PROJECT_DIR}/manifests/base/kibana.yaml" -n "${NAMESPACE}"

# 2. Wait for databases
echo "⏳ Waiting for MongoDB..."
kubectl wait --for=condition=ready pod -l app=website-db-vault-kaf-redis-arg-kust-kyv-gra-loki-temp-pgui,component=mongodb -n "${NAMESPACE}" --timeout=300s

echo "⏳ Waiting for Elasticsearch..."
kubectl wait --for=condition=ready pod -l app=website-db-vault-kaf-redis-arg-kust-kyv-gra-loki-temp-pgui,component=elasticsearch -n "${NAMESPACE}" --timeout=300s

# 3. Initialize MongoDB
echo "🔧 Initializing MongoDB..."
kubectl wait --for=condition=complete job/mongodb-init -n "${NAMESPACE}" --timeout=300s

# 4. Deploy Spark
echo "⚡ Deploying Apache Spark..."
kubectl apply -f "${PROJECT_DIR}/manifests/base/spark-master.yaml" -n "${NAMESPACE}"
kubectl apply -f "${PROJECT_DIR}/manifests/base/spark-worker.yaml" -n "${NAMESPACE}"

# 5. Deploy Spring Boot
echo "🌱 Deploying Spring Boot..."
kubectl apply -f "${PROJECT_DIR}/manifests/base/spring-app-deployment.yaml" -n "${NAMESPACE}"

# 6. Wait for services
echo "⏳ Waiting for Spark Master..."
kubectl wait --for=condition=ready pod -l app=website-db-vault-kaf-redis-arg-kust-kyv-gra-loki-temp-pgui,component=spark-master -n "${NAMESPACE}" --timeout=300s

echo "⏳ Waiting for Spring Boot..."
kubectl wait --for=condition=ready pod -l app=website-db-vault-kaf-redis-arg-kust-kyv-gra-loki-temp-pgui,component=spring-app -n "${NAMESPACE}" --timeout=300s

# 7. Update FastAPI with new routes
echo "🔄 Updating FastAPI deployment..."
kubectl rollout restart deployment/fastapi-web-app -n "${NAMESPACE}"
kubectl wait --for=condition=ready pod -l app=website-db-vault-kaf-redis-arg-kust-kyv-gra-loki-temp-pgui,component=fastapi -n "${NAMESPACE}" --timeout=300s

# 8. Update Ingress
echo "🌐 Updating Ingress..."
kubectl apply -f "${PROJECT_DIR}/manifests/base/ingress-extended.yaml" -n "${NAMESPACE}"

# 9. Update monitoring
echo "📊 Updating monitoring..."
kubectl apply -f "${PROJECT_DIR}/manifests/base/monitoring-extended.yaml" -n "${NAMESPACE}"

echo ""
echo "✅ Extended stack deployment complete!"
echo ""
echo "🌐 Access points:"
echo "   Main App:        http://app.website-db-vault-kaf-redis-arg-kust-kyv-gra-loki-temp-pgui.local"
echo "   New Survey:      http://app.website-db-vault-kaf-redis-arg-kust-kyv-gra-loki-temp-pgui.local/new-survey"
echo "   Spring Boot API: http://spring.website-db-vault-kaf-redis-arg-kust-kyv-gra-loki-temp-pgui.local"
echo "   Spark UI:        http://spark.website-db-vault-kaf-redis-arg-kust-kyv-gra-loki-temp-pgui.local"
echo "   Kibana:          http://kibana.website-db-vault-kaf-redis-arg-kust-kyv-gra-loki-temp-pgui.local"
echo "   Grafana:         http://grafana.website-db-vault-kaf-redis-arg-kust-kyv-gra-loki-temp-pgui.local"
echo "   PgAdmin:         http://pgadmin.website-db-vault-kaf-redis-arg-kust-kyv-gra-loki-temp-pgui.local"
echo "   Kafka UI:        http://kafka-ui.website-db-vault-kaf-redis-arg-kust-kyv-gra-loki-temp-pgui.local"
echo ""
echo "🔍 Check pods:"
echo "   kubectl get pods -n ${NAMESPACE}"
echo ""
echo "📈 Check services:"
echo "   kubectl get svc -n ${NAMESPACE}"
BASH

chmod +x "${PROJECT_DIR}/deploy-extended.sh"

# ========== 15. README ROZBUDOWANY ==========

cat > "${PROJECT_DIR}/README-EXTENDED.md" <<'MD'
# 🚀 Rozbudowany All-in-One Stack: Spring Boot + JavaScript + Spark + ELK

## 📋 Nowa Architektura
