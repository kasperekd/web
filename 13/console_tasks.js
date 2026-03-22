// Задание 1: переменные и вывод
let username = "my name";
let bonusBalance = 1000;
console.log("Пользователь " + username);
console.log("Баланс " + bonusBalance);

// Задание 2: расчёт баланса за 7 дней
// Покупка раз в два дня (дни 1, 3, 5, 7 — всего 4 покупки), каждый день сгорает 3 балла
let calculatedBalance = 0;
for (let day = 1; day <= 7; day++) {
    if (day % 2 === 1) {
        calculatedBalance += 50;
    }
    calculatedBalance -= 3;
}
console.log("Итоговый баланс через 7 дней: " + calculatedBalance);

// Задание 3: история сообщений
let messages = [
    "Пойдем гулять в парк?",
    "Кажется, дождь собирается...",
    "Давай, сегодня в кино лучше?",
    "Встречаемся через час..."
];

for (let i = 0; i < messages.length; i++) {
    if (i % 2 === 0) {
        console.log("Вы: " + messages[i]);
    } else {
        console.log("Друг: " + messages[i]);
    }
}

// Задание 4: поиск по массиву
function searchMessages(keyword) {
    let found = messages.filter(function(msg) {
        return msg.includes(keyword);
    });
    if (found.length > 0) {
        found.forEach(function(msg) {
            console.log("Найдено: " + msg);
        });
    } else {
        console.log("Сообщения со словом \"" + keyword + "\" не найдены");
    }
}

searchMessages("кино");
