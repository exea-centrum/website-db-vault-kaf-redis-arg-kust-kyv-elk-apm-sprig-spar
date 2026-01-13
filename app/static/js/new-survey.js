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
        setTimeout(() => { messageDiv.style.display = 'none'; }, 5000);
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
