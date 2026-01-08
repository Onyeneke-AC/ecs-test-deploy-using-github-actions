const path = require("path");
const fs = require("fs");

const express = require("express");
const bodyParser = require("body-parser");
const axios = require("axios");

const filePath = path.join(__dirname, process.env.TASKS_FOLDER, "tasks.txt");

const app = express();

app.use(bodyParser.json());

app.use((req, res, next) => {
  res.setHeader("Access-Control-Allow-Origin", "*");
  res.setHeader("Access-Control-Allow-Methods", "POST,GET,OPTIONS");
  res.setHeader("Access-Control-Allow-Headers", "Content-Type,Authorization");
  next();
});

// const extractAndVerifyToken = async (headers) => {
//   if (!headers.authorization) {
//     throw new Error('No token provided.');
//   }
//   const token = headers.authorization.split(' ')[1]; // expects Bearer TOKEN

//   const response = await axios.get(`http://${process.env.AUTH_ADDRESS}/verify-token/` + token);
//   return response.data.uid;
// };

const extractAndVerifyToken = async (headers) => {
  console.log(
    "TEMP – skipping token verification. Header:",
    headers.authorization
  );
  // Accept everything during debugging:
  return "debug-usersss";
};

// Health check endpoint
app.get("/health", (req, res) => {
  res.status(200).json({
    status: "ok",
    message: "Tasks service is healthy",
    timestamp: new Date().toISOString(),
  });
});

app.get(["/tasks", "/api/tasks"], async (req, res) => {
  try {
    const uid = await extractAndVerifyToken(req.headers);
    fs.readFile(filePath, (err, data) => {
      if (err) {
        console.log(err);
        return res
          .status(500)
          .json({ message: "Loading the tasks failed. Chai!!!" });
      }
      const strData = data.toString();
      const entries = strData.split("TASK_SPLIT");
      entries.pop();
      console.log(entries);
      const tasks = entries.map((json) => JSON.parse(json));
      res.status(200).json({
        message: "Tasks loaded. I too good. No be lie my brotherrr",
        tasks: tasks,
      });
    });
  } catch (err) {
    console.log(err);
    return res
      .status(401)
      .json({ message: err.message || "Failed to load tasks." });
  }
});

app.post(["/tasks", "/api/tasks"], async (req, res) => {
  try {
    const uid = await extractAndVerifyToken(req.headers);
    const text = req.body.text;
    const title = req.body.title;
    const task = { title, text };
    const jsonTask = JSON.stringify(task);
    fs.appendFile(filePath, jsonTask + "TASK_SPLIT", (err) => {
      if (err) {
        console.log(err);
        return res
          .status(500)
          .json({ message: "Storing the task failed. As howww." });
      }
      res
        .status(201)
        .json({
          message: "Task stored. Crazyyy and maddddd.",
          createdTask: task,
        });
    });
  } catch (err) {
    return res.status(401).json({ message: "Could not verify token." });
  }
});

app.listen(8000);
