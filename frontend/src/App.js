import React, { useState, useEffect, useCallback } from "react";

import "./App.css";
import TaskList from "./components/TaskList";
import NewTask from "./components/NewTask";

function App() {
  const [tasks, setTasks] = useState([]);

  const fetchTasks = useCallback(function () {
    fetch("/api/tasks", {
      headers: {
        Authorization: "Bearer abcd",
      },
    })
      .then(function (response) {
        if (!response.ok) {
          // Log status so we can see 404 / 500 / 502, etc.
          throw new Error("Request failed with status " + response.status);
        }
        return response.json();
      })
      .then(function (jsonData) {
        console.log("Fetched tasks payload:", jsonData);

        // Be defensive about the shape of the data
        if (Array.isArray(jsonData.tasks)) {
          setTasks(jsonData.tasks);
        } else if (Array.isArray(jsonData)) {
          // In case backend returns an array directly
          setTasks(jsonData);
        } else {
          console.warn("Unexpected tasks shape, defaulting to []");
          setTasks([]);
        }
      })
      .catch(function (error) {
        console.error("Error fetching tasks:", error);
        // Don't let the app crash just because of the request
        setTasks([]);
      });
  }, []);

  useEffect(
    function () {
      fetchTasks();
    },
    [fetchTasks]
  );

  function addTaskHandler(task) {
    fetch("/api/tasks", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: "Bearer abcd",
      },
      body: JSON.stringify(task),
    })
      .then(function (response) {
        if (!response.ok) {
          throw new Error("Failed to create task, status " + response.status);
        }
        return response.json();
      })
      .then(function (resData) {
        console.log("Created task:", resData);

        // Option A: Append to existing tasks in state
        if (resData.createdTask) {
          setTasks((prevTasks) => prevTasks.concat(resData.createdTask));
        } else {
          // fallback: re-fetch full list if backend doesn't return createdTask
          fetchTasks();
        }
      })
      .catch(function (error) {
        console.error("Error creating task:", error);
      });
  }

  return (
    <div className="App">
      <section>
        <NewTask onAddTask={addTaskHandler} />
      </section>
      <section>
        <button onClick={fetchTasks}>Fetch Tasks for trial</button>
        <TaskList tasks={tasks} />
      </section>
    </div>
  );
}

export default App;
